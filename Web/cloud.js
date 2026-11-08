"use strict";
import { readWorkspace, writeWorkspace, workspaceManifest } from "./cloud-archive.js";
import { noteWinsMerge } from "./core.js";

const CLOUDKIT_SCRIPT = "https://cdn.apple-cloudkit.com/ck/2/cloudkit.js";
const CONTAINER_ID = "iCloud.com.stickeynote.app";
const RECORD_TYPE = "StickeyWorkspace";
const EMPTY_CONTENT = { title: "", text: "", items: [], strokes: [] };
let sdkPromise;

/**
 * Native-compatible private CloudKit sync. No server key is used in a browser.
 * getArchive returns an object or JSON string; mergeArchive receives an object.
 * onStatus(message, state) is called for authentication, progress, and failures.
 * The SDK renders Apple auth buttons into apple-sign-in-button / apple-sign-out-button.
 */
export function createCloudSync({ getArchive, mergeArchive, onStatus = () => {}, config = globalThis.STICKEY_CLOUD_CONFIG } = {}) {
    if (typeof getArchive !== "function" || typeof mergeArchive !== "function") {
        throw new TypeError("Cloud sync requires getArchive and mergeArchive callbacks.");
    }
    const configured = !!(config?.apiToken && !config.apiToken.includes("YOUR_"));
    let state = { configured, authenticated: false, syncing: false, lastSynced: null, error: null };
    let container, database, initializing, inFlight, timer, poll, disposed = false, generation = 0, authGeneration = 0;
    let lastUploaded = null;
    const archiveCache = new Map();
    const deviceID = persistentDeviceID();
    const recordName = `device-${deviceID}`;
    const accountBindingKey = `StickeyNote.cloudKitAccount.${config?.containerIdentifier || CONTAINER_ID}.${config?.environment === "production" ? "production" : "development"}`;
    let activeAccountID = null;

    function report(message, update = {}) {
        state = { ...state, ...update };
        onStatus(message, { ...state });
    }

    async function connect() {
        if (disposed) return false;
        if (!configured) {
            report("iCloud isn’t connected for this installation. Notes are saved in this browser.");
            return false;
        }
        if (initializing) return initializing;
        initializing = (async () => {
            try {
                report("Connecting to iCloud…", { error: null });
                const CloudKit = await loadCloudKit();
                if (disposed) return false;
                if (!container) {
                    CloudKit.configure({
                        containers: [{
                            containerIdentifier: config.containerIdentifier || CONTAINER_ID,
                            environment: config.environment === "production" ? "production" : "development",
                            apiTokenAuth: {
                                apiToken: config.apiToken,
                                persist: true,
                                signInButton: { id: "apple-sign-in-button", theme: "black" },
                                signOutButton: { id: "apple-sign-out-button", theme: "black" }
                            }
                        }]
                    });
                    container = CloudKit.getDefaultContainer();
                    database = container.privateCloudDatabase;
                }
                const identity = await container.setUpAuth();
                if (disposed) return false;
                applyIdentity(identity);
                watchAuthentication(!!identity);
                if (state.authenticated) await sync();
                return state.authenticated;
            } catch (error) {
                if (!disposed) report(errorMessage(error), { error: errorMessage(error), syncing: false });
                return false;
            } finally { initializing = null; }
        })();
        return initializing;
    }

    function applyIdentity(identity) {
        generation += 1;
        lastUploaded = null;
        archiveCache.clear();
        clearInterval(poll);
        clearTimeout(timer);
        activeAccountID = null;
        if (identity) {
            const accountID = identity.userRecordName;
            if (!accountID) {
                report("Apple could not verify this account. Sync is paused; your notes remain saved here.", { authenticated: false, syncing: false });
                return;
            }
            try {
                const bound = globalThis.localStorage?.getItem(accountBindingKey);
                if (bound && bound !== accountID) {
                    report("This workspace belongs to a different iCloud account. Sign back into that account; your local notes are safe.", { authenticated: false, syncing: false, accountMismatch: true });
                    return;
                }
                if (!globalThis.localStorage) throw new Error("Storage unavailable");
                globalThis.localStorage.setItem(accountBindingKey, accountID);
            } catch {
                report("This browser couldn’t save your account connection. Sync is paused to keep your accounts separate.", { authenticated: false, syncing: false });
                return;
            }
            activeAccountID = accountID;
            report("Connected to iCloud", { authenticated: true, accountMismatch: false, error: null });
            poll = setInterval(() => {
                if (globalThis.document?.visibilityState !== "hidden") void sync();
            }, 30_000);
        } else {
            report("Sign in with Apple to sync your notes.", { authenticated: false, syncing: false, accountMismatch: false, error: null });
        }
    }

    function watchAuthentication(signedIn) {
        const watcher = ++authGeneration;
        const event = signedIn ? container.whenUserSignsOut() : container.whenUserSignsIn();
        event.then(identity => {
            if (disposed || watcher !== authGeneration) return;
            applyIdentity(signedIn ? null : identity);
            watchAuthentication(!signedIn);
            if (!signedIn && identity) void sync();
        }).catch(error => {
            if (!disposed && watcher === authGeneration) report(errorMessage(error), { error: errorMessage(error) });
        });
    }

    async function verifyAccount() {
        const identity = await container.setUpAuth();
        if (identity?.userRecordName === activeAccountID && state.authenticated) return true;
        applyIdentity(identity);
        watchAuthentication(!!identity);
        return false;
    }

    function schedule() {
        clearTimeout(timer);
        if (!state.authenticated || disposed) return;
        timer = setTimeout(() => void sync(), 1_200);
    }

    async function sync() {
        if (disposed || !state.authenticated || !database) return false;
        if (inFlight) return inFlight;
        if (globalThis.navigator?.onLine === false) {
            report("You’re offline. Notes are saved here; iCloud will retry.");
            return false;
        }
        const current = generation;
        const active = () => !disposed && generation === current && state.authenticated;
        inFlight = (async () => {
            report("Syncing with iCloud…", { syncing: true, error: null });
            try {
                if (!await verifyAccount() || !active()) return false;
                const records = await queryAll(database);
                if (!active()) return false;
                const loadedArchives = new Map();
                let waitingForUpload = false;
                for (const record of records) {
                    const key = `${record.recordName}:${record.recordChangeTag || ""}`;
                    let archive = archiveCache.get(key);
                    if (!archive) {
                        let usedPrevious = false;
                        archive = parseArchive(await readWorkspace(record, database, { onFallback: () => { usedPrevious = true; } }));
                        if (usedPrevious) waitingForUpload = true;
                        else archiveCache.set(key, archive);
                    }
                    loadedArchives.set(record.recordName, archive);
                    if (!active()) return false;
                }
                if (!await verifyAccount() || !active()) return false;
                for (const archive of loadedArchives.values()) {
                    await mergeArchive(structuredClone(archive));
                    if (!active()) return false;
                }
                if (waitingForUpload) {
                    report("Some iCloud changes are still arriving. Notes are saved here.", { syncing: false });
                    return false;
                }
                // Defense in depth: even a currently unlocked note is exported only
                // as ciphertext, never as its plaintext editor content or history.
                const merged = safeArchive(await getArchive());
                if (!await verifyAccount() || !active()) return false;
                const json = JSON.stringify(merged);
                const protectedNotes = new Map(merged.notes.filter(note => note.encryptedContent).map(note => [note.id, note]));
                for (const record of records) {
                    if (record.recordName === recordName || !protectedNotes.size) continue;
                    const archive = structuredClone(loadedArchives.get(record.recordName));
                    const manifest = workspaceManifest(record);
                    let changed = !!manifest?.previous;
                    archive.notes = archive.notes.map(note => {
                        const newest = protectedNotes.get(note.id);
                        if (newest && noteWinsMerge(newest, note) && JSON.stringify(note) !== JSON.stringify(newest)) {
                            changed = true;
                            return structuredClone(newest);
                        }
                        return note;
                    });
                    if (changed) {
                        const otherDevice = manifest?.deviceID || record.recordName.replace(/^device-/, "");
                        await writeWorkspace(archive, record, otherDevice, database, { retainPrevious: false, isActive: active });
                    }
                }
                const own = records.find(record => record.recordName === recordName);
                if (!active()) return false;
                if (json !== lastUploaded || !own) {
                    await writeWorkspace(merged, own, deviceID, database, { retainPrevious: !protectedNotes.size, isActive: active });
                }
                if (!active()) return false;
                const cacheKeys = new Set(records.map(record => `${record.recordName}:${record.recordChangeTag || ""}`));
                for (const key of archiveCache.keys()) if (!cacheKeys.has(key)) archiveCache.delete(key);
                lastUploaded = json;
                report("Up to date with iCloud", { syncing: false, lastSynced: new Date(), error: null });
                return true;
            } catch (error) {
                if (active()) report(errorMessage(error), { syncing: false, error: errorMessage(error) });
                return false;
            } finally { inFlight = null; }
        })();
        return inFlight;
    }

    function dispose() {
        disposed = true;
        generation += 1;
        authGeneration += 1;
        clearInterval(poll);
        clearTimeout(timer);
        globalThis.removeEventListener?.("online", handleOnline);
        globalThis.document?.removeEventListener("visibilitychange", handleVisibility);
    }
    const handleOnline = () => { if (state.authenticated) void sync(); };
    const handleVisibility = () => {
        if (globalThis.document?.visibilityState === "visible" && state.authenticated) void sync();
    };
    globalThis.addEventListener?.("online", handleOnline);
    globalThis.document?.addEventListener("visibilitychange", handleVisibility);

    return {
        ready: Promise.resolve(), connect, refreshAuth: connect, sync, schedule, dispose,
        get state() { return { ...state }; }
    };
}

async function queryAll(database) {
    let response = assertResponse(await database.performQuery({ recordType: RECORD_TYPE }, { resultsLimit: 100 }));
    const records = [...(response.records || [])];
    const seenMarkers = new Set();
    while (response.continuationMarker || response.moreComing) {
        const marker = response.continuationMarker;
        if (!marker || seenMarkers.has(marker)) throw new Error("iCloud returned an incomplete page. Please try syncing again.");
        seenMarkers.add(marker);
        // CloudKit JS accepts its entire prior QueryResponse to continue safely.
        response = assertResponse(await database.performQuery(response));
        records.push(...(response.records || []));
    }
    return records;
}

function assertResponse(response) {
    if (response?.hasErrors || response?.errors?.length) throw response.errors[0];
    if (!response) throw new Error("iCloud returned an empty response. Please try again.");
    return response;
}

function parseArchive(value) {
    const archive = typeof value === "string" ? JSON.parse(value) : structuredClone(value);
    if (archive?.version !== 1 || !Array.isArray(archive.notes) || !Array.isArray(archive.groups)) {
        throw new Error("An iCloud workspace uses an unsupported format. Local notes are unchanged.");
    }
    return archive;
}

function safeArchive(value) {
    const archive = parseArchive(value);
    archive.notes = archive.notes.map(note => note.encryptedContent
        ? { ...note, content: { ...EMPTY_CONTENT, items: [], strokes: [] }, history: [] }
        : note);
    return archive;
}

function persistentDeviceID() {
    const key = "StickeyNote.cloudKitDeviceID";
    try {
        let value = globalThis.localStorage?.getItem(key);
        if (!value) {
            value = crypto.randomUUID();
            globalThis.localStorage?.setItem(key, value);
        }
        return value;
    } catch { return crypto.randomUUID(); }
}

function loadCloudKit() {
    if (globalThis.CloudKit) return Promise.resolve(globalThis.CloudKit);
    if (sdkPromise) return sdkPromise;
    sdkPromise = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = CLOUDKIT_SCRIPT;
        script.async = true;
        const timeout = setTimeout(() => finish(new Error("Apple’s sign-in service took too long to load. Please try again.")), 20_000);
        function finish(error) {
            clearTimeout(timeout);
            script.onload = script.onerror = null;
            if (error) { script.remove(); sdkPromise = null; reject(error); }
            else resolve(globalThis.CloudKit);
        }
        script.onload = () => finish(globalThis.CloudKit ? null : new Error("Apple’s sign-in service is unavailable."));
        script.onerror = () => finish(new Error("Could not reach Apple. Check your connection and try again."));
        document.head.append(script);
    });
    return sdkPromise;
}

function errorMessage(error) {
    const code = error?.ckErrorCode || error?.serverErrorCode || error?.code;
    switch (code) {
    case "AUTHENTICATION_REQUIRED":
    case "AUTHENTICATION_FAILED": return "Sign in with Apple again to reconnect iCloud.";
    case "NETWORK_ERROR":
    case "SERVICE_UNAVAILABLE": return "iCloud is temporarily unavailable. Your notes are saved here.";
    case "CONFLICT": return "Another device changed a note. iCloud will retry the merge.";
    case "QUOTA_EXCEEDED": return "Your iCloud storage is full. Notes remain saved in this browser.";
    case "CONFIGURATION_ERROR": return "iCloud isn’t configured for this installation. Notes are saved in this browser.";
    default: return error?.message || error?.reason || "Could not sync with iCloud. Your notes remain saved here.";
    }
}
