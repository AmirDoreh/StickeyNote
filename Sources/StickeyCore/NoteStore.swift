import Foundation
import Observation
import CryptoKit

@MainActor @Observable
public final class NoteStore {
    public private(set) var notes: [StickyNote] = []
    public private(set) var groups: [NoteGroup] = []
    public private(set) var saveStatus = "Saved on this device"
    public var errorMessage: String?
    public var selectedNoteID: UUID?
    public let directory: URL
    public static let autoLockOptions: [TimeInterval] = [30, 60, 120, 300, 600, 900]
    private static let autoLockPreferenceKey = "StickeyNote.autoLockSeconds"
    private var autoLockInterval: TimeInterval = 120
    /// Device-local duration measured from authentication, never extended by editing.
    public var autoLockSeconds: TimeInterval {
        get { autoLockInterval }
        set {
            let interval = Self.autoLockOptions.contains(newValue) ? newValue : 120
            guard interval != autoLockInterval else { return }
            relockExpiredNotes()
            autoLockInterval = interval
            defaults.set(interval, forKey: Self.autoLockPreferenceKey)
            relockExpiredNotes()
            for id in Array(unlockedAt.keys) { scheduleAutoLock(id) }
        }
    }
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var unlockedKeys: [UUID: SymmetricKey] = [:]
    @ObservationIgnored private var unlockedAt: [UUID: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var autoLockTasks: [UUID: Task<Void, Never>] = [:]
    // A monotonic clock includes sleep and cannot be extended by changing the system date.
    @ObservationIgnored var autoLockNow: () -> ContinuousClock.Instant = { ContinuousClock.now }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var securityGeneration: [UUID: UInt64] = [:]
    @ObservationIgnored private var deletedGroups: [NoteGroup] = []
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var savedRevision: UInt64 = 0
    @ObservationIgnored private var replaceBackup = false
    @ObservationIgnored private var readOnly = false
    @ObservationIgnored private var modifiedAt = Date()
    @ObservationIgnored private let persistence: NotePersistence

    public init(directory: URL? = nil, seed: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedInterval = defaults.double(forKey: Self.autoLockPreferenceKey)
        autoLockInterval = Self.autoLockOptions.contains(savedInterval) ? savedInterval : 120
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickeyNote", isDirectory: true)
        self.directory = base
        persistence = NotePersistence(directory: base)
        let primary = base.appendingPathComponent("notes.json")
        if FileManager.default.fileExists(atPath: primary.path) {
            do {
                let archive = try ArchiveCodec.decode(Data(contentsOf: primary))
                notes = archive.notes.map(\.persisted); groups = archive.groups.filter { $0.deletedAt == nil }
                deletedGroups = archive.groups.filter { $0.deletedAt != nil }; modifiedAt = archive.modifiedAt
            } catch {
                let backup = base.appendingPathComponent("notes.backup.json")
                if let data = try? Data(contentsOf: backup), let archive = try? ArchiveCodec.decode(data) {
                    notes = archive.notes.map(\.persisted); groups = archive.groups.filter { $0.deletedAt == nil }
                    deletedGroups = archive.groups.filter { $0.deletedAt != nil }; modifiedAt = archive.modifiedAt
                    errorMessage = "Your last saved backup was recovered. The damaged file has not been changed yet."
                } else {
                    readOnly = true
                    errorMessage = "Your notes could not be opened. The original files are preserved in \(base.path). Restore a valid backup to continue."
                    saveStatus = "Recovery needed"
                }
            }
        } else if seed {
            let samples = Self.samples()
            notes = samples.notes; groups = samples.groups
            markChanged()
        }
        selectedNoteID = nil
    }

    deinit {
        for task in autoLockTasks.values { task.cancel() }
    }

    @discardableResult
    public func createNote(kind: NoteKind = .text, groupID: UUID? = nil) -> UUID {
        let note = StickyNote(kind: kind, content: NoteContent(items: kind == .checklist ? [ChecklistItem()] : []), groupID: groupID)
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        markChanged()
        return note.id
    }

    public func updateNote(_ id: UUID, _ mutate: (inout StickyNote) -> Void) {
        relockExpiredNotes()
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let previous = notes[index]
        var updated = previous
        mutate(&updated)
        guard updated != previous else { return }
        // Identity and the protection envelope are controlled by the store, never an editor.
        updated.id = previous.id
        updated.encryptedContent = previous.encryptedContent
        updated.protectionUpdatedAt = previous.protectionUpdatedAt
        updated.protectionRevisionID = previous.protectionRevisionID
        updated.history = previous.history
        updated.createdAt = previous.createdAt
        updated.fontSize = min(96, max(8, updated.fontSize.isFinite ? updated.fontSize : 18))
        if previous.content != updated.content {
            guard !isLocked(id) else { errorMessage = NoteSecurityError.locked.localizedDescription; return }
            if previous.content != NoteContent(),
               previous.history.last.map({ Date().timeIntervalSince($0.date) >= 30 }) ?? true {
                updated.history.append(NoteSnapshot(content: previous.content))
            }
            if updated.history.count > 50 { updated.history.removeFirst(updated.history.count - 50) }
        }
        updated.updatedAt = max(Date(), previous.updatedAt.addingTimeInterval(0.001))
        updated.revisionID = UUID()
        do { try refreshEncryption(&updated) }
        catch { errorMessage = error.localizedDescription; return }
        notes[index] = updated
        markChanged()
    }

    public func deleteNote(_ id: UUID) {
        updateNote(id) { $0.deletedAt = Date() }
        relockNote(id)
        if selectedNoteID == id { selectedNoteID = notes.first(where: { $0.deletedAt == nil })?.id }
    }
    public func restoreNote(_ id: UUID) {
        updateNote(id) { $0.deletedAt = nil }
        selectedNoteID = id
    }
    @discardableResult
    public func duplicateNote(_ id: UUID) -> UUID? {
        relockExpiredNotes()
        guard var copy = notes.first(where: { $0.id == id }), !isLocked(id) else {
            errorMessage = NoteSecurityError.locked.localizedDescription; return nil
        }
        copy.id = UUID(); copy.revisionID = UUID(); copy.createdAt = Date(); copy.updatedAt = Date()
        copy.deletedAt = nil; copy.history = []; copy.isPinned = false
        copy.content.title = copy.displayTitle + " copy"
        if let key = unlockedKeys[id] { unlockedKeys[copy.id] = key }
        do { try refreshEncryption(&copy) }
        catch { errorMessage = error.localizedDescription; unlockedKeys[copy.id] = nil; return nil }
        notes.insert(copy, at: 0); selectedNoteID = copy.id; markChanged()
        if copy.isPasswordProtected {
            // Copying a note must not renew its authenticated viewing window.
            if let started = unlockedAt[id] {
                unlockedAt[copy.id] = started
                scheduleAutoLock(copy.id)
            } else {
                relockNote(copy.id)
            }
        }
        return copy.id
    }

    @discardableResult
    public func addGroup(name: String, symbol: String = "folder") -> UUID {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = NoteGroup(name: clean.isEmpty ? "New group" : clean, symbol: symbol)
        groups.append(group); markChanged(); return group.id
    }
    public func renameGroup(_ id: UUID, name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = clean; groups[index].revisionID = UUID(); groups[index].updatedAt = max(Date(), groups[index].updatedAt.addingTimeInterval(0.001)); markChanged()
    }
    public func deleteGroup(_ id: UUID) {
        if var group = groups.first(where: { $0.id == id }) {
            group.deletedAt = Date(); group.revisionID = UUID(); group.updatedAt = max(Date(), group.updatedAt.addingTimeInterval(0.001)); deletedGroups.append(group)
        }
        groups.removeAll { $0.id == id }
        for index in notes.indices where notes[index].groupID == id {
            notes[index].groupID = nil; notes[index].revisionID = UUID(); notes[index].updatedAt = max(Date(), notes[index].updatedAt.addingTimeInterval(0.001))
        }
        markChanged()
    }
    public func restoreSnapshot(noteID: UUID, snapshotID: UUID) {
        relockExpiredNotes()
        guard let index = notes.firstIndex(where: { $0.id == noteID }), !isLocked(noteID),
              let snapshot = notes[index].history.first(where: { $0.id == snapshotID }) else { return }
        var note = notes[index]
        note.history.append(NoteSnapshot(content: note.content))
        note.content = snapshot.content; note.revisionID = UUID(); note.updatedAt = max(Date(), note.updatedAt.addingTimeInterval(0.001))
        if note.history.count > 50 { note.history.removeFirst(note.history.count - 50) }
        do { try refreshEncryption(&note) }
        catch { errorMessage = error.localizedDescription; return }
        notes[index] = note; markChanged()
    }

    public func isLocked(_ id: UUID) -> Bool {
        guard let note = notes.first(where: { $0.id == id }) else { return false }
        return note.isPasswordProtected && unlockedKeys[id] == nil
    }

    public func lockNote(_ id: UUID, password: String) async throws {
        guard password.count >= 8 else { throw NoteSecurityError.passwordTooShort }
        try await protectNote(id, credential: password)
    }

    public func lockNote(_ id: UUID, pin: String) async throws {
        guard (4...12).contains(pin.utf8.count), pin.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw NoteSecurityError.invalidPIN
        }
        try await protectNote(id, credential: pin)
    }

    /// The app generates this secret and protects it with Apple's device-owner authentication.
    public func lockNoteWithAppleCredential(_ id: UUID, credential: String, credentialID: UUID,
                                           expectedGeneration: UInt64? = nil) async throws {
        guard credential.utf8.count >= 32 else { throw NoteSecurityError.unavailable }
        try await protectNote(id, credential: credential, credentialID: credentialID,
                              expectedGeneration: expectedGeneration)
    }

    /// Re-encrypt an authenticated note directly, never persisting an unprotected intermediate.
    public func convertToAppleAuthentication(_ id: UUID, credential: String, credentialID: UUID,
                                            expectedGeneration: UInt64? = nil) async throws {
        guard credential.utf8.count >= 32 else { throw NoteSecurityError.unavailable }
        try await protectNote(id, credential: credential, credentialID: credentialID,
                              replacingProtection: true, expectedGeneration: expectedGeneration)
    }

    private func protectNote(_ id: UUID, credential: String, credentialID: UUID? = nil,
                             replacingProtection: Bool = false, expectedGeneration: UInt64? = nil) async throws {
        relockExpiredNotes()
        let generation = securityGeneration[id, default: 0]
        if let expectedGeneration, expectedGeneration != generation { throw NoteSecurityError.locked }
        guard let note = notes.first(where: { $0.id == id }) else { return }
        guard replacingProtection ? (note.isPasswordProtected && !isLocked(id)) : !note.isPasswordProtected else {
            throw NoteSecurityError.locked
        }
        let salt = try NoteCryptography.randomSalt()
        let key = try await Task.detached(priority: .userInitiated) {
            try NoteCryptography.key(password: credential, salt: salt, iterations: NoteCryptography.iterations)
        }.value
        relockExpiredNotes()
        guard securityGeneration[id, default: 0] == generation else { throw NoteSecurityError.locked }
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var current = notes[index]
        guard replacingProtection ? (current.isPasswordProtected && !isLocked(id)) : !current.isPasswordProtected else {
            throw NoteSecurityError.locked
        }
        let previousProtectionDate = current.protectionVersionDate
        current.encryptedContent = try NoteCryptography.encrypt(current, key: key, salt: salt, iterations: NoteCryptography.iterations)
        current.encryptedContent?.credentialKind = credentialID == nil ? nil : "apple"
        current.encryptedContent?.credentialID = credentialID
        current.protectionUpdatedAt = max(Date(), (previousProtectionDate ?? .distantPast).addingTimeInterval(0.001))
        current.protectionRevisionID = UUID()
        current.updatedAt = max(Date(), current.updatedAt.addingTimeInterval(0.001))
        current.revisionID = UUID()
        current.content = NoteContent(); current.history = []
        notes[index] = current; clearUnlockSession(id)
        securityGeneration[id, default: 0] &+= 1
        replaceBackup = true
        markChanged()
        try await persist()
    }

    /// Capture before starting a biometric prompt so a relock invalidates its result.
    public func securityGenerationToken(for id: UUID) -> UInt64 {
        securityGeneration[id, default: 0]
    }

    public func unlockNote(_ id: UUID, password: String, expectedGeneration: UInt64? = nil) async throws {
        relockExpiredNotes()
        if let expectedGeneration, securityGeneration[id, default: 0] != expectedGeneration {
            throw NoteSecurityError.locked
        }
        guard let payload = notes.first(where: { $0.id == id })?.encryptedContent else { return }
        let generation = securityGeneration[id, default: 0]
        let key = try await Task.detached(priority: .userInitiated) {
            try NoteCryptography.key(password: password, salt: payload.salt, iterations: payload.iterations)
        }.value
        guard securityGeneration[id, default: 0] == generation else { throw NoteSecurityError.locked }
        guard let index = notes.firstIndex(where: { $0.id == id }), let current = notes[index].encryptedContent else { return }
        let body = try NoteCryptography.decrypt(current, noteID: id, key: key)
        unlockedKeys[id] = key
        notes[index].content = body.content; notes[index].history = body.history
        unlockedAt[id] = autoLockNow()
        scheduleAutoLock(id)
    }

    public func relockNote(_ id: UUID) {
        securityGeneration[id, default: 0] &+= 1
        clearUnlockSession(id)
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].isPasswordProtected else { return }
        // Every mutation refreshes the encrypted body, so no asynchronous work is needed here.
        notes[index].content = NoteContent(); notes[index].history = []
    }
    public func relockAll() {
        for id in notes.filter(\.isPasswordProtected).map(\.id) { relockNote(id) }
    }
    public func removePassword(_ id: UUID, password: String, expectedGeneration: UInt64? = nil) async throws {
        try await unlockNote(id, password: password, expectedGeneration: expectedGeneration)
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        guard notes[index].isPasswordProtected else { return }
        notes[index].protectionUpdatedAt = max(Date(), (notes[index].protectionVersionDate ?? notes[index].updatedAt).addingTimeInterval(0.001))
        notes[index].protectionRevisionID = UUID()
        notes[index].encryptedContent = nil; notes[index].revisionID = UUID(); notes[index].updatedAt = max(Date(), notes[index].updatedAt.addingTimeInterval(0.001))
        clearUnlockSession(id)
        securityGeneration[id, default: 0] &+= 1
        markChanged()
        try await persist()
    }

    public func exportArchive() throws -> Data {
        try ArchiveCodec.encode(NoteArchive(notes: notes.map(\.persisted), groups: groups + deletedGroups, modifiedAt: modifiedAt))
    }
    /// Imports merge by note identity and modification time, preserving local notes and trash.
    public func importArchive(_ data: Data) throws {
        try mergeArchive(data)
        if readOnly { readOnly = false; replaceBackup = true; markChanged() }
    }
    public func mergeArchive(_ data: Data) throws {
        let incoming = try ArchiveCodec.decode(data)
        var byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var changed = false
        for note in incoming.notes {
            if let local = byID[note.id], local.winsMerge(over: note) { continue }
            byID[note.id] = note.persisted
            clearUnlockSession(note.id)
            securityGeneration[note.id, default: 0] &+= 1
            if note.isPasswordProtected { replaceBackup = true }
            changed = true
        }
        var groupsByID = Dictionary(uniqueKeysWithValues: (groups + deletedGroups).map { ($0.id, $0) })
        for group in incoming.groups {
            if let local = groupsByID[group.id], local.updatedAt > group.updatedAt ||
                (local.updatedAt == group.updatedAt && (local.revisionID?.uuidString ?? "") >= (group.revisionID?.uuidString ?? "")) { continue }
            groupsByID[group.id] = group; changed = true
        }
        if changed {
            groups = groupsByID.values.filter { $0.deletedAt == nil }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            deletedGroups = groupsByID.values.filter { $0.deletedAt != nil }
            notes = byID.values.sorted { $0.createdAt > $1.createdAt }
            markChanged()
        }
    }

    public func flush() async {
        do { try await persist() }
        catch { errorMessage = "Your latest changes could not be saved: \(error.localizedDescription)"; saveStatus = "Couldn’t save" }
    }

    /// Also called before protected mutations so a delayed timer cannot extend access.
    public func relockExpiredNotes() {
        let now = autoLockNow()
        for (id, started) in Array(unlockedAt) where now >= started.advanced(by: .seconds(autoLockSeconds)) {
            relockNote(id)
        }
    }

    private func clearUnlockSession(_ id: UUID) {
        autoLockTasks.removeValue(forKey: id)?.cancel()
        unlockedAt[id] = nil
        unlockedKeys[id] = nil
    }

    private func scheduleAutoLock(_ id: UUID) {
        autoLockTasks.removeValue(forKey: id)?.cancel()
        guard let started = unlockedAt[id] else { return }
        let deadline = started.advanced(by: .seconds(autoLockSeconds))
        let remaining = autoLockNow().duration(to: deadline)
        guard remaining > .zero else { relockNote(id); return }
        let generation = securityGeneration[id, default: 0]
        autoLockTasks[id] = Task { [weak self] in
            do { try await Task.sleep(for: remaining) } catch { return }
            guard let self, !Task.isCancelled,
                  self.securityGeneration[id, default: 0] == generation,
                  self.unlockedAt[id] == started else { return }
            self.relockExpiredNotes()
            // A duration change or an early scheduler wake still uses the original deadline.
            if self.unlockedAt[id] != nil { self.scheduleAutoLock(id) }
        }
    }

    private func refreshEncryption(_ note: inout StickyNote) throws {
        guard let payload = note.encryptedContent, let key = unlockedKeys[note.id] else { return }
        note.encryptedContent = try NoteCryptography.encrypt(note, key: key, salt: payload.salt, iterations: payload.iterations)
    }
    private func markChanged() {
        revision &+= 1; modifiedAt = Date()
        guard !readOnly else { return }
        saveStatus = "Saving…"
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await self?.flush()
        }
    }
    private func persist() async throws {
        guard !readOnly, savedRevision < revision else { return }
        let currentRevision = revision
        let resetBackup = replaceBackup
        let data = try exportArchive()
        try await persistence.write(data, revision: currentRevision, replaceBackup: resetBackup)
        savedRevision = max(savedRevision, currentRevision)
        if revision == currentRevision { saveStatus = "Saved on this device"; replaceBackup = false }
    }
}
