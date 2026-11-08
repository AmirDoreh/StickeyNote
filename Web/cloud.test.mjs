import test from "node:test";
import assert from "node:assert/strict";
import { createCloudSync } from "./cloud.js";
import { readWorkspace, writeWorkspace, workspaceManifest } from "./cloud-archive.js";

const config = { apiToken: "test-token", environment: "development" };
const content = text => ({ title: "Title", text, items: [], strokes: [] });
const note = (id, updatedAt, text) => ({ id, updatedAt, createdAt: 1, kind: "text", content: content(text), history: [], color: "butter", font: "system", fontSize: 18, isPinned: false });
const archive = notes => ({ version: 1, modifiedAt: 1, notes, groups: [] });
const record = (name, value) => ({ recordName: name, recordType: "StickeyWorkspace", recordChangeTag: "original", fields: { archive: { value: JSON.stringify(value) } } });

function mockDatabase(initial = [], pageSize = 100) {
    const records = new Map(initial.map(r => [r.recordName, structuredClone(r)]));
    const saves = [];
    let version = 0, pages = 0;
    return {
        records, saves, get pages() { return pages; },
        async performQuery(query) {
            pages += 1;
            const all = [...records.values()].filter(r => r.recordType === "StickeyWorkspace");
            const start = Number(query.continuationMarker || 0);
            const more = start + pageSize < all.length;
            return { records: structuredClone(all.slice(start, start + pageSize)), moreComing: more,
                ...(more ? { continuationMarker: String(start + pageSize) } : {}) };
        },
        async fetchRecords(names) {
            const values = names.map(name => records.get(typeof name === "string" ? name : name.recordName));
            if (values.some(r => !r)) return { hasErrors: true, errors: [{ ckErrorCode: "NOT_FOUND" }] };
            return { records: structuredClone(values) };
        },
        async saveRecords(values) {
            const result = [];
            for (const value of values) {
                const existing = records.get(value.recordName);
                if (existing && existing.recordChangeTag !== value.recordChangeTag) return { hasErrors: true, errors: [{ ckErrorCode: "CONFLICT" }] };
                saves.push(structuredClone(value));
                const saved = { ...structuredClone(value), recordChangeTag: `version-${++version}` };
                records.set(value.recordName, saved);
                result.push(saved);
            }
            return { records: result };
        },
        async deleteRecords(values) {
            for (const value of values) records.delete(value.recordName);
            return { records: values.map(value => ({ ...value, deleted: true })) };
        }
    };
}

function mockSDK(database, { user = "test-user", storage = new Map() } = {}) {
    let signOut;
    const container = {
        privateCloudDatabase: database,
        setUpAuth: async () => ({ userRecordName: user }),
        whenUserSignsIn: () => new Promise(() => {}),
        whenUserSignsOut: () => new Promise(resolve => { signOut = resolve; })
    };
    globalThis.CloudKit = { configure() {}, getDefaultContainer: () => container };
    globalThis.localStorage = { getItem: key => key === "StickeyNote.cloudKitDeviceID" ? "test-device" : storage.get(key) ?? null,
        setItem: (key, value) => storage.set(key, value) };
    return { signOut: () => signOut?.(), switchAccount(value) { user = value; }, storage };
}

test("sync merges paginated legacy records and sanitizes protected content in every workspace", async () => {
    const locked = { ...note("secret", 20, "UNLOCKED SECRET"), history: [{ content: content("OLD SECRET") }], encryptedContent: { salt: "salt", iterations: 310000, sealedData: "ciphertext" } };
    const local = archive([locked]);
    const db = mockDatabase([record("device-other", archive([note("secret", 10, "REMOTE SECRET")])), record("device-test-device", archive([]))], 1);
    mockSDK(db);
    const cloud = createCloudSync({ config, getArchive: () => local, mergeArchive(incoming) {
        const map = new Map(local.notes.map(n => [n.id, n]));
        for (const value of incoming.notes) if (!map.has(value.id) || map.get(value.id).updatedAt < value.updatedAt) map.set(value.id, value);
        local.notes = [...map.values()];
    } });
    try {
        assert.equal(await cloud.connect(), true);
        assert.equal(db.pages, 2);
        for (const name of ["device-other", "device-test-device"]) {
            const saved = await readWorkspace(db.records.get(name), db);
            assert.ok(!JSON.stringify(saved).includes("SECRET"));
            assert.equal(saved.notes[0].encryptedContent.sealedData, "ciphertext");
            assert.deepEqual(saved.notes[0].history, []);
        }
        assert.equal(local.notes[0].content.text, "UNLOCKED SECRET");
        const count = db.saves.length;
        await cloud.sync();
        assert.equal(db.saves.length, count, "unchanged workspace must not upload again");
    } finally { cloud.dispose(); }
});

test("multi-megabyte Unicode archive round-trips through bounded native-compatible chunks", async () => {
    const original = archive([note("large", 1, "🌏 café 漢字\n".repeat(150_000))]);
    const db = mockDatabase();
    const saved = await writeWorkspace(original, null, "large-device", db);
    assert.ok(workspaceManifest(saved).current.count > 5);
    assert.deepEqual(await readWorkspace(saved, db), original);
    for (const chunk of db.saves.filter(r => r.recordType === "StickeyWorkspaceChunk")) {
        assert.ok(new TextEncoder().encode(chunk.fields.archive.value).length < 500_000);
    }
    assert.equal(db.saves.at(-1).recordType, "StickeyWorkspace", "manifest commits after all chunks");
});

test("newer protection epochs scrub later stale plaintext metadata edits", async () => {
    const locked = { ...note("protected", 20, ""), protectionUpdatedAt: 20, protectionRevisionID: "B",
        encryptedContent: { salt: "salt", iterations: 600000, sealedData: "ciphertext" } };
    const stale = note("protected", 1000, "STALE PLAINTEXT");
    stale.color = "mint";
    const db = mockDatabase([record("device-stale", archive([stale]))]);
    mockSDK(db);
    const cloud = createCloudSync({ config, getArchive: () => archive([locked]), mergeArchive() {} });
    try {
        await cloud.connect();
        const synced = await readWorkspace(db.records.get("device-stale"), db);
        assert.equal(synced.notes[0].encryptedContent.sealedData, "ciphertext");
        assert.ok(!JSON.stringify(synced).includes("STALE PLAINTEXT"));
    } finally { cloud.dispose(); }
});

test("partial upload never commits a manifest, leaving the previous workspace readable", async () => {
    const db = mockDatabase();
    const first = await writeWorkspace(archive([note("n", 1, "safe")]), null, "device", db);
    const originalSave = db.saveRecords;
    db.saveRecords = async values => values[0].recordType === "StickeyWorkspaceChunk"
        ? { hasErrors: true, errors: [{ ckErrorCode: "NETWORK_ERROR" }] } : originalSave(values);
    await assert.rejects(writeWorkspace(archive([note("n", 2, "new")]), first, "device", db));
    assert.equal((await readWorkspace(db.records.get(first.recordName), db)).notes[0].content.text, "safe");
});

test("missing or corrupted current chunks fall back to the prior verified generation", async () => {
    const db = mockDatabase();
    const first = await writeWorkspace(archive([note("n", 1, "safe")]), null, "device", db);
    const second = await writeWorkspace(archive([note("n", 2, "latest")]), first, "device", db);
    const manifest = workspaceManifest(second);
    const name = `device-device-${manifest.current.generation}-0`;
    const chunk = db.records.get(name);
    const envelope = JSON.parse(chunk.fields.archive.value);
    envelope.payload = btoa("corrupted bytes");
    chunk.fields.archive.value = JSON.stringify(envelope);
    assert.equal((await readWorkspace(second, db)).notes[0].content.text, "safe");
    db.records.delete(name);
    assert.equal((await readWorkspace(second, db)).notes[0].content.text, "safe");
});

test("privacy commit removes prior plaintext generations after new ciphertext is committed", async () => {
    const db = mockDatabase();
    const first = await writeWorkspace(archive([note("n", 1, "secret")]), null, "device", db);
    const originalChunk = [...db.records.keys()].find(name => name !== first.recordName);
    const second = await writeWorkspace(archive([{ ...note("n", 2, ""), encryptedContent: { sealedData: "encrypted" } }]), first, "device", db, { retainPrevious: false });
    assert.equal(workspaceManifest(second).previous, undefined);
    assert.equal(db.records.has(originalChunk), false);
});

test("fallback snapshots never overwrite an incomplete generation and retry when its chunks arrive", async () => {
    const db = mockDatabase();
    const first = await writeWorkspace(archive([note("n", 1, "safe")]), null, "remote", db);
    const second = await writeWorkspace(archive([note("n", 2, "latest")]), first, "remote", db);
    const manifest = workspaceManifest(second);
    const name = `device-remote-${manifest.current.generation}-0`;
    const delayed = db.records.get(name);
    db.records.delete(name);
    const savedBefore = db.saves.length;
    let local = archive([]);
    mockSDK(db);
    const cloud = createCloudSync({ config, getArchive: () => local, mergeArchive(incoming) {
        if (!local.notes.length || incoming.notes[0].updatedAt > local.notes[0].updatedAt) local = incoming;
    } });
    try {
        await cloud.connect();
        assert.equal(local.notes[0].content.text, "safe");
        assert.equal(db.saves.length, savedBefore);
        assert.equal(cloud.state.lastSynced, null);
        db.records.set(name, delayed);
        assert.equal(await cloud.sync(), true);
        assert.equal(local.notes[0].content.text, "latest");
        assert.ok(cloud.state.lastSynced);
    } finally { cloud.dispose(); }
});

test("record conflicts are reported and never force-overwrite another device", async () => {
    const db = mockDatabase();
    db.saveRecords = async () => ({ hasErrors: true, errors: [{ ckErrorCode: "CONFLICT" }] });
    mockSDK(db);
    const cloud = createCloudSync({ config, getArchive: () => archive([]), mergeArchive() {} });
    try {
        await cloud.connect();
        assert.match(cloud.state.error, /retry the merge/);
        assert.equal(cloud.state.lastSynced, null);
    } finally { cloud.dispose(); }
});

test("signing out during a request prevents subsequent merge and upload", async () => {
    let resolveQuery, merges = 0, saves = 0;
    const auth = mockSDK({
        performQuery: () => new Promise(resolve => { resolveQuery = resolve; }),
        saveRecords: async () => { saves += 1; return { records: [] }; }
    });
    const cloud = createCloudSync({ config, getArchive: () => archive([]), mergeArchive() { merges += 1; } });
    try {
        const connecting = cloud.connect();
        await new Promise(resolve => setImmediate(resolve));
        auth.signOut();
        await new Promise(resolve => setImmediate(resolve));
        resolveQuery({ records: [record("remote", archive([note("private", 1, "text")]))] });
        await connecting;
        assert.equal(cloud.state.authenticated, false);
        assert.equal(merges, 0);
        assert.equal(saves, 0);
    } finally { cloud.dispose(); }
});

test("unconfigured sync stays local and does not invoke the SDK", async () => {
    let called = false;
    globalThis.CloudKit = { configure() { called = true; } };
    const cloud = createCloudSync({ config: null, getArchive: () => archive([]), mergeArchive() {} });
    try {
        assert.equal(await cloud.connect(), false);
        assert.equal(called, false);
    } finally { cloud.dispose(); }
});

test("account changes during an active session cannot merge or upload another account's workspace", async () => {
    const db = mockDatabase();
    const auth = mockSDK(db);
    let merges = 0;
    const cloud = createCloudSync({ config, getArchive: () => archive([]), mergeArchive() { merges += 1; } });
    try {
        await cloud.connect();
        const savedBefore = db.saves.length, mergedBefore = merges;
        auth.switchAccount("different-user");
        assert.equal(await cloud.sync(), false);
        assert.equal(cloud.state.authenticated, false);
        assert.equal(cloud.state.accountMismatch, true);
        assert.equal(db.saves.length, savedBefore);
        assert.equal(merges, mergedBefore);
    } finally { cloud.dispose(); }
});

test("persisted workspace account binding also blocks a different account after reload", async () => {
    const storage = new Map();
    const db = mockDatabase();
    mockSDK(db, { user: "first-user", storage });
    const first = createCloudSync({ config, getArchive: () => archive([]), mergeArchive() {} });
    await first.connect();
    first.dispose();
    const before = db.saves.length;
    mockSDK(db, { user: "second-user", storage });
    const second = createCloudSync({ config, getArchive: () => archive([]), mergeArchive() { assert.fail("Must not merge other account"); } });
    try {
        assert.equal(await second.connect(), false);
        assert.equal(second.state.accountMismatch, true);
        assert.equal(db.saves.length, before);
    } finally { second.dispose(); }
});

test("an account switch while records are downloading blocks their merge", async () => {
    const db = mockDatabase();
    const auth = mockSDK(db);
    let merges = 0;
    const cloud = createCloudSync({ config, getArchive: () => archive([]), mergeArchive() { merges += 1; } });
    try {
        await cloud.connect();
        const mergedBefore = merges, savedBefore = db.saves.length;
        const query = db.performQuery;
        db.performQuery = async (...args) => { const response = await query(...args); auth.switchAccount("different-user"); return response; };
        assert.equal(await cloud.sync(), false);
        assert.equal(merges, mergedBefore);
        assert.equal(db.saves.length, savedBefore);
        assert.equal(cloud.state.accountMismatch, true);
    } finally { cloud.dispose(); }
});
