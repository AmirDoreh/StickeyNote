"use strict";

// Shared wire format with CloudArchiveTransport.swift. UTF-8 bytes are split
// before base64 encoding, so emoji and other multibyte text round-trip exactly.
const CHUNK_SIZE = 360_000;
const MAX_ARCHIVE_BYTES = 100_000_000; // Same defensive import bound as the native codec.
const CHUNK_TYPE = "StickeyWorkspaceChunk";
const encoder = new TextEncoder();

export function workspaceManifest(record) {
    const value = JSON.parse(record.fields.archive.value);
    return value?.chunkVersion ? value : null;
}

export async function readWorkspace(record, database, { onFallback = () => {} } = {}) {
    const manifest = workspaceManifest(record);
    if (!manifest) return JSON.parse(record.fields.archive.value); // Legacy format.
    if (manifest.chunkVersion !== 1) throw new Error("This iCloud workspace requires a newer version of StickeyNote.");
    try { return await readGeneration(manifest.current, manifest.deviceID, database); }
    catch (error) {
        if (!manifest.previous) throw error;
        const archive = await readGeneration(manifest.previous, manifest.deviceID, database);
        onFallback();
        return archive;
    }
}

async function readGeneration(generation, deviceID, database) {
    if (!Number.isInteger(generation.count) || generation.count < 1 || generation.count > 300 ||
        !Number.isInteger(generation.byteCount) || generation.byteCount < 1 || generation.byteCount > MAX_ARCHIVE_BYTES) throw incomplete();
    const names = chunkNames(generation, deviceID);
    const bytes = new Uint8Array(generation.byteCount);
    let position = 0;
    for (let start = 0; start < names.length; start += 100) {
        const batch = names.slice(start, start + 100);
        const response = check(await database.fetchRecords(batch, { desiredKeys: ["archive"] }));
        const records = new Map(response.records.map(record => [record.recordName, record]));
        for (let offset = 0; offset < batch.length; offset += 1) {
            const record = records.get(batch[offset]);
            if (!record) throw incomplete();
            const chunk = JSON.parse(record.fields.archive.value);
            if (chunk.chunkVersion !== 1 || chunk.deviceID !== deviceID || chunk.generation !== generation.generation ||
                chunk.index !== start + offset || chunk.count !== generation.count) throw incomplete();
            const part = decodeBase64(chunk.payload);
            if (part.length > CHUNK_SIZE || position + part.length > bytes.length) throw incomplete();
            bytes.set(part, position);
            position += part.length;
        }
    }
    if (position !== bytes.length || await sha256(bytes) !== generation.sha256) throw incomplete();
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

export async function writeWorkspace(archive, existing, deviceID, database, { retainPrevious = true, isActive = () => true } = {}) {
    const bytes = encoder.encode(JSON.stringify(archive));
    if (bytes.length > MAX_ARCHIVE_BYTES) throw new Error("This archive exceeds the 100 MB safety limit. Export a backup before reducing attachment or history data.");
    const previous = existing ? workspaceManifest(existing) : null;
    const generation = {
        generation: crypto.randomUUID().toUpperCase(),
        count: Math.max(1, Math.ceil(bytes.length / CHUNK_SIZE)),
        byteCount: bytes.length,
        sha256: await sha256(bytes),
        committedAt: Date.now()
    };
    const names = chunkNames(generation, deviceID);
    for (let start = 0; start < names.length; start += 30) {
        if (!isActive()) throw cancelled();
        const chunks = names.slice(start, start + 30).map((recordName, offset) => {
            const index = start + offset;
            const envelope = {
                chunkVersion: 1, deviceID, generation: generation.generation,
                index, count: generation.count,
                payload: encodeBase64(bytes.subarray(index * CHUNK_SIZE, Math.min((index + 1) * CHUNK_SIZE, bytes.length)))
            };
            return { recordType: CHUNK_TYPE, recordName, fields: { archive: { value: JSON.stringify(envelope), type: "STRING" } } };
        });
        check(await database.saveRecords(chunks));
    }
    if (!isActive()) throw cancelled();
    const manifest = { chunkVersion: 1, deviceID, current: generation,
        ...(retainPrevious && previous ? { previous: previous.current } : {}) };
    const record = {
        recordType: "StickeyWorkspace", recordName: existing?.recordName || `device-${deviceID}`,
        ...(existing?.recordChangeTag ? { recordChangeTag: existing.recordChangeTag } : {}),
        fields: {
            archive: { value: JSON.stringify(manifest), type: "STRING" },
            modifiedAt: { value: Date.now(), type: "TIMESTAMP" },
            deviceName: { value: existing?.fields?.deviceName?.value || "Web browser", type: "STRING" }
        }
    };
    // Commit only after every chunk exists. Never use a force-update operation.
    const response = check(await database.saveRecords([record]));
    const committed = response.records.find(item => item.recordName === record.recordName);
    if (!committed) throw incomplete();
    if (previous && isActive()) {
        let obsolete = previous.previous ? chunkNames(previous.previous, previous.deviceID) : [];
        if (!retainPrevious) obsolete = obsolete.concat(chunkNames(previous.current, previous.deviceID));
        for (let start = 0; start < obsolete.length && isActive(); start += 100) {
            // Cleanup never invalidates the committed generation. Fetch current
            // tags and tolerate interrupted cleanup; the notes remain readable.
            try {
                const old = check(await database.fetchRecords(obsolete.slice(start, start + 100), { desiredKeys: [] }));
                check(await database.deleteRecords(old.records.map(({ recordName, recordChangeTag }) => ({ recordName, recordChangeTag }))));
            } catch { /* Retryable storage cleanup; no note content is lost. */ }
        }
    }
    return committed;
}

function chunkNames(generation, deviceID) {
    return Array.from({ length: generation.count }, (_, index) => `device-${deviceID}-${generation.generation}-${index}`);
}

async function sha256(bytes) {
    const hash = await crypto.subtle.digest("SHA-256", bytes);
    return Array.from(new Uint8Array(hash), value => value.toString(16).padStart(2, "0")).join("");
}

function encodeBase64(bytes) {
    let value = "";
    for (let start = 0; start < bytes.length; start += 16_384) value += String.fromCharCode(...bytes.subarray(start, start + 16_384));
    return btoa(value);
}

function decodeBase64(value) { return Uint8Array.from(atob(value), character => character.charCodeAt(0)); }
function incomplete() { return new Error("An iCloud upload is incomplete or damaged. Local notes are safe; sync will retry."); }
function cancelled() { return new Error("iCloud sync stopped."); }
function check(response) {
    if (response?.hasErrors || response?.errors?.length) throw response.errors[0];
    if (!response?.records) throw incomplete();
    return response;
}
