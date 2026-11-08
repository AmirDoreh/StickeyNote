import Foundation
import CloudKit
import Combine
import Observation
import CryptoKit
import StickeyCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Interoperable with CloudKit JS: one JSON archive per device in the user's
/// private database, with timestamp-based note merging and deletion tombstones.
@MainActor
final class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()
    static let containerIdentifier = "iCloud.com.stickeynote.app"
    static let recordType = "StickeyWorkspace"
    @Published private(set) var isEnabled = false
    @Published private(set) var isSyncing = false
    @Published private(set) var status = "iCloud sync is off"
    @Published private(set) var lastSynced: Date?
    private weak var store: NoteStore?
    private var database: CKDatabase?
    private var cloudContainer: CKContainer?
    private var activeAccountID: String?
    private var accountObserver: NSObjectProtocol?
    private var pollTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var session = UUID()
    private var observing = false
    private var lastUploaded: NoteArchive?
    private var archiveCache: [String: NoteArchive] = [:]
    private let deviceID: String

    init() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "StickeyNote.cloudKitDeviceID") { deviceID = id }
        else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: "StickeyNote.cloudKitDeviceID")
        }
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stop()
                self.status = "iCloud account changed. Sync is paused; your notes remain saved on this device."
            }
        }
    }

    deinit { if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) } }

    var wasEnabled: Bool { UserDefaults.standard.bool(forKey: "StickeyNote.cloudKitEnabled") }

    func start(store: NoteStore) {
        guard !isEnabled else { return }
        self.store = store
        // A bare Swift package executable has no CloudKit provisioning. This
        // also prevents CKContainer from throwing an Objective-C exception.
        guard Bundle.main.object(forInfoDictionaryKey: "StickeyCloudKitEnabled") as? Bool == true else {
            status = "iCloud requires the signed Xcode app and CloudKit setup."
            return
        }
        let currentSession = UUID()
        session = currentSession
        status = "Connecting to iCloud…"
        Task {
            do {
                let container = CKContainer(identifier: Self.containerIdentifier)
                let account = try await container.accountStatus()
                guard session == currentSession else { return }
                guard account == .available else {
                    status = "Sign in to iCloud in Settings to sync your notes."
                    return
                }
                let accountID = try await container.userRecordID().recordName
                guard session == currentSession else { return }
                guard bindAccount(accountID, store: store) else { return }
                activeAccountID = accountID
                cloudContainer = container
                database = container.privateCloudDatabase
                isEnabled = true
                UserDefaults.standard.set(true, forKey: "StickeyNote.cloudKitEnabled")
                observeStore()
                await syncNow()
                pollTask = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                        await self?.syncNow()
                    }
                }
            } catch { status = Self.message(for: error) }
        }
    }

    func stop() {
        session = UUID()
        pollTask?.cancel()
        debounceTask?.cancel()
        database = nil
        cloudContainer = nil
        activeAccountID = nil
        store = nil
        observing = false
        isEnabled = false
        isSyncing = false
        lastUploaded = nil
        archiveCache = [:]
        status = "iCloud sync is off"
        UserDefaults.standard.set(false, forKey: "StickeyNote.cloudKitEnabled")
    }

    func syncNow() async {
        guard isEnabled, !isSyncing, let database, let cloudContainer, let activeAccountID, let store else { return }
        isSyncing = true
        let currentSession = session
        status = "Syncing with iCloud…"
        defer { if session == currentSession { isSyncing = false } }
        do {
            let account = try await cloudContainer.userRecordID().recordName
            guard session == currentSession else { return }
            guard account == activeAccountID else {
                stop()
                status = "A different iCloud account is signed in. Sync is paused to keep your accounts separate."
                return
            }
            let records = try await fetchAll(from: database)
            guard session == currentSession else { return }
            var archives: [CKRecord.ID: NoteArchive] = [:]
            var waitingForUpload = false
            for record in records {
                let cacheKey = record.recordID.recordName + ":" + (record.recordChangeTag ?? "")
                let archive: NoteArchive
                if let cached = archiveCache[cacheKey] { archive = cached }
                else {
                    let downloaded = try await CloudArchiveTransport.read(record, database: database)
                    archive = try ArchiveCodec.decode(downloaded.data)
                    if downloaded.usedPrevious { waitingForUpload = true }
                    else { archiveCache[cacheKey] = archive }
                }
                guard session == currentSession else { return }
                archives[record.recordID] = archive
            }
            let mergeAccount = try await cloudContainer.userRecordID().recordName
            guard session == currentSession else { return }
            guard mergeAccount == activeAccountID else {
                stop()
                status = "A different iCloud account is signed in. Sync is paused to keep your accounts separate."
                return
            }
            for record in records {
                if let archive = archives[record.recordID] { try store.mergeArchive(ArchiveCodec.encode(archive)) }
            }
            if waitingForUpload {
                status = "Some iCloud changes are still arriving. Notes are saved here."
                await store.flush()
                return
            }
            let archiveData = try store.exportArchive()
            let merged = try ArchiveCodec.decode(archiveData)
            let ownID = CKRecord.ID(recordName: "device-\(deviceID)")
            let uploadAccount = try await cloudContainer.userRecordID().recordName
            guard session == currentSession else { return }
            guard uploadAccount == activeAccountID else {
                stop()
                status = "A different iCloud account is signed in. Sync is paused to keep your accounts separate."
                return
            }

            // Remove obsolete plaintext copies after a note is password locked.
            // Optimistic save conflicts protect edits made during this merge.
            let protected = Dictionary(uniqueKeysWithValues: merged.notes.filter(\.isPasswordProtected).map { ($0.id, $0) })
            if !protected.isEmpty {
                for record in records where record.recordID != ownID {
                    guard var archive = archives[record.recordID] else { continue }
                    var changed = CloudArchiveTransport.manifest(in: record)?.previous != nil
                    for index in archive.notes.indices {
                        let old = archive.notes[index]
                        if let newest = protected[old.id], newest.winsMerge(over: old),
                           old != newest.persisted {
                            archive.notes[index] = newest.persisted
                            changed = true
                        }
                    }
                    if changed {
                        let otherDevice = CloudArchiveTransport.manifest(in: record)?.deviceID
                            ?? String(record.recordID.recordName.dropFirst("device-".count))
                        _ = try await CloudArchiveTransport.write(ArchiveCodec.encode(archive), to: record,
                                                                 deviceID: otherDevice, database: database,
                                                                 retainPrevious: false, isActive: { self.session == currentSession })
                    }
                }
            }

            if lastUploaded != merged || !records.contains(where: { $0.recordID == ownID }) {
                let own = records.first(where: { $0.recordID == ownID }) ?? CKRecord(recordType: Self.recordType, recordID: ownID)
                #if os(macOS)
                own["deviceName"] = (Host.current().localizedName ?? "Mac") as CKRecordValue
                #else
                own["deviceName"] = UIDevice.current.name as CKRecordValue
                #endif
                _ = try await CloudArchiveTransport.write(archiveData, to: own, deviceID: deviceID, database: database,
                                                         retainPrevious: protected.isEmpty, isActive: { self.session == currentSession })
            }
            guard session == currentSession else { return }
            lastUploaded = merged
            let validCacheKeys = Set(records.map { $0.recordID.recordName + ":" + ($0.recordChangeTag ?? "") })
            archiveCache = archiveCache.filter { validCacheKeys.contains($0.key) }
            lastSynced = Date()
            status = "Up to date with iCloud"
            await store.flush()
        } catch {
            guard session == currentSession else { return }
            status = Self.message(for: error)
        }
    }

    private func bindAccount(_ accountID: String, store: NoteStore) -> Bool {
        let workspace = SHA256.hash(data: Data(store.directory.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let key = "StickeyNote.cloudKitAccount.\(Self.containerIdentifier).\(workspace)"
        if let bound = UserDefaults.standard.string(forKey: key), bound != accountID {
            status = "This workspace belongs to a different iCloud account. Sign back into that account; your local notes are safe."
            UserDefaults.standard.set(false, forKey: "StickeyNote.cloudKitEnabled")
            return false
        }
        UserDefaults.standard.set(accountID, forKey: key)
        return true
    }

    private func fetchAll(from database: CKDatabase) async throws -> [CKRecord] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        var page = try await database.records(matching: query, resultsLimit: 100)
        var records: [CKRecord] = []
        while true {
            for (_, result) in page.matchResults { records.append(try result.get()) }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 100)
        }
        return records
    }

    private func observeStore() {
        guard !observing, isEnabled, let store else { return }
        observing = true
        let observedSession = session
        withObservationTracking {
            _ = store.notes
            _ = store.groups
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.session == observedSession else { return }
                self.observing = false
                guard self.isEnabled else { return }
                self.debounceTask?.cancel()
                self.debounceTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
                    await self?.syncNow()
                }
                self.observeStore()
            }
        }
    }

    private static func message(for error: Error) -> String {
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated: return "Sign in to iCloud in Settings to sync your notes."
            case .networkUnavailable, .networkFailure: return "You’re offline. Notes are saved here; iCloud will retry."
            case .serverRecordChanged: return "Another device changed a note. iCloud will retry the merge."
            case .quotaExceeded: return "Your iCloud storage is full. Notes remain saved on this device."
            case .badContainer, .missingEntitlement: return "CloudKit needs a provisioned app and configured container."
            case .unknownItem: return "Create the StickeyWorkspace CloudKit schema before enabling sync."
            default: return "iCloud: \(error.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}
