import XCTest
@testable import StickeyCore

@MainActor
final class NoteStoreTests: XCTestCase {
    private var directories: [URL] = []
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StickeyCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }
    override func tearDown() async throws {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
    }

    func testAutosaveRoundTripAndTrashRestore() async throws {
        let location = try directory()
        let store = NoteStore(directory: location, seed: false)
        let group = store.addGroup(name: "Research")
        let id = store.createNote(kind: .checklist, groupID: group)
        store.updateNote(id) { note in
            note.content.title = "Launch"
            note.content.items = [ChecklistItem(text: "Ship it", isCompleted: true)]
            note.color = .sage
        }
        await store.flush()
        let reopened = NoteStore(directory: location, seed: false)
        XCTAssertEqual(reopened.notes.first?.content.title, "Launch")
        XCTAssertEqual(reopened.notes.first?.content.items.first?.isCompleted, true)
        XCTAssertEqual(reopened.notes.first?.groupID, group)
        reopened.deleteNote(id)
        XCTAssertNotNil(reopened.notes.first?.deletedAt)
        reopened.restoreNote(id)
        XCTAssertNil(reopened.notes.first?.deletedAt)
    }

    func testProtectedContentAndHistoryNeverReachArchiveOrBackup() async throws {
        let location = try directory()
        let store = NoteStore(directory: location, seed: false)
        let id = store.createNote()
        store.updateNote(id) { $0.content = NoteContent(title: "private-title", text: "first-secret") }
        store.updateNote(id) { $0.content.text = "second-secret" }
        await store.flush()
        try await store.lockNote(id, password: "correct horse battery")
        XCTAssertTrue(store.isLocked(id))
        XCTAssertEqual(store.notes.first?.content, NoteContent())
        for name in ["notes.json", "notes.backup.json"] {
            let disk = try String(contentsOf: location.appendingPathComponent(name), encoding: .utf8)
            XCTAssertFalse(disk.contains("first-secret"))
            XCTAssertFalse(disk.contains("second-secret"))
            XCTAssertFalse(disk.contains("private-title"))
        }
        try await store.unlockNote(id, password: "correct horse battery")
        XCTAssertEqual(store.notes.first?.content.text, "second-secret")
        XCTAssertTrue(store.notes.first?.history.contains { $0.content.text == "first-secret" } == true)
        store.updateNote(id) { $0.content.text = "third-secret" }
        await store.flush()
        let archive = try store.exportArchive()
        XCTAssertFalse(String(decoding: archive, as: UTF8.self).contains("third-secret"))
        store.relockAll()
        let reopened = NoteStore(directory: location, seed: false)
        try await reopened.unlockNote(id, password: "correct horse battery")
        XCTAssertEqual(reopened.notes.first?.content.text, "third-secret")
    }

    func testWrongPasswordAndCiphertextIdentityBinding() async throws {
        let store = NoteStore(directory: try directory(), seed: false)
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Keep this safe" }
        try await store.lockNote(id, password: "test-password")
        do {
            try await store.unlockNote(id, password: "wrong-password")
            XCTFail("Wrong password must fail")
        } catch { XCTAssertEqual(error as? NoteSecurityError, .incorrectPassword) }
        XCTAssertTrue(store.isLocked(id))
        var tampered = try ArchiveCodec.decode(store.exportArchive())
        let changedID = UUID()
        tampered.notes[0].id = changedID
        let other = NoteStore(directory: try directory(), seed: false)
        try other.importArchive(ArchiveCodec.encode(tampered))
        do {
            try await other.unlockNote(changedID, password: "test-password")
            XCTFail("Ciphertext copied to another note must fail authentication")
        } catch { XCTAssertEqual(error as? NoteSecurityError, .incorrectPassword) }
    }

    func testHistoryRestoreKeepsCurrentContentRecoverable() throws {
        let store = NoteStore(directory: try directory(), seed: false)
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Original" }
        store.updateNote(id) { $0.content.text = "Revised" }
        let snapshot = try XCTUnwrap(store.notes.first?.history.first)
        store.restoreSnapshot(noteID: id, snapshotID: snapshot.id)
        XCTAssertEqual(store.notes.first?.content.text, "Original")
        XCTAssertEqual(store.notes.first?.history.last?.content.text, "Revised")
    }

    func testMergeUsesNewestNoteAndRetainsDeletionTombstones() throws {
        let store = NoteStore(directory: try directory(), seed: false)
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Local" }
        var remote = try ArchiveCodec.decode(store.exportArchive())
        remote.notes[0].content.text = "Remote"
        remote.notes[0].updatedAt = Date().addingTimeInterval(60)
        remote.notes[0].deletedAt = Date()
        try store.mergeArchive(ArchiveCodec.encode(remote))
        XCTAssertEqual(store.notes.first?.content.text, "Remote")
        XCTAssertNotNil(store.notes.first?.deletedAt)
        var stale = remote
        stale.notes[0].updatedAt = Date().addingTimeInterval(-60)
        stale.notes[0].deletedAt = nil
        try store.mergeArchive(ArchiveCodec.encode(stale))
        XCTAssertNotNil(store.notes.first?.deletedAt)
    }

    func testGroupRenameAndDeletionMerge() throws {
        let store = NoteStore(directory: try directory(), seed: false)
        let id = store.addGroup(name: "Original")
        var remote = try ArchiveCodec.decode(store.exportArchive())
        remote.groups[0].name = "Renamed"
        remote.groups[0].updatedAt = Date().addingTimeInterval(60)
        try store.mergeArchive(ArchiveCodec.encode(remote))
        XCTAssertEqual(store.groups.first?.name, "Renamed")
        remote.groups[0].deletedAt = Date()
        remote.groups[0].updatedAt = Date().addingTimeInterval(120)
        try store.mergeArchive(ArchiveCodec.encode(remote))
        XCTAssertFalse(store.groups.contains { $0.id == id })
        XCTAssertNotNil(try ArchiveCodec.decode(store.exportArchive()).groups.first?.deletedAt)
    }

    func testCorruptFilesAreNotOverwritten() async throws {
        let location = try directory()
        let url = location.appendingPathComponent("notes.json")
        let damaged = Data("not valid json".utf8)
        try damaged.write(to: url)
        let store = NoteStore(directory: location, seed: true)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.notes.isEmpty)
        _ = store.createNote()
        await store.flush()
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }

    func testEqualTimestampConflictsConvergeByRevisionID() throws {
        let store = NoteStore(directory: try directory(), seed: false)
        let id = store.createNote()
        var archive = try ArchiveCodec.decode(store.exportArchive())
        archive.notes[0].revisionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        archive.notes[0].updatedAt = Date().addingTimeInterval(60)
        archive.notes[0].content.text = "Earlier revision"
        try store.mergeArchive(ArchiveCodec.encode(archive))
        var winner = archive
        winner.notes[0].revisionID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        winner.notes[0].content.text = "Winning revision"
        try store.mergeArchive(ArchiveCodec.encode(winner))
        try store.mergeArchive(ArchiveCodec.encode(archive))
        XCTAssertEqual(store.notes.first?.content.text, "Winning revision")
        store.updateNote(id) { $0.content.text = "New local revision" }
        XCTAssertGreaterThan(try XCTUnwrap(store.notes.first?.updatedAt), winner.notes[0].updatedAt)
    }

    func testBackgroundRelockCancelsInFlightUnlock() async throws {
        let store = NoteStore(directory: try directory(), seed: false)
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Only while active" }
        try await store.lockNote(id, password: "test-password")
        let task = Task { try await store.unlockNote(id, password: "test-password") }
        await Task.yield()
        store.relockAll()
        do { try await task.value; XCTFail("A backgrounded unlock must be cancelled") }
        catch { XCTAssertEqual(error as? NoteSecurityError, .locked) }
        XCTAssertTrue(store.isLocked(id))
        XCTAssertEqual(store.notes.first?.content, NoteContent())
    }

    func testRecoveryReadsBackupWithoutOverwritingDamagedPrimary() async throws {
        let location = try directory()
        let store = NoteStore(directory: location, seed: false)
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Recoverable" }
        await store.flush()
        let url = location.appendingPathComponent("notes.json")
        let damaged = Data("damaged".utf8)
        try damaged.write(to: url)
        let recovered = NoteStore(directory: location, seed: false)
        XCTAssertEqual(recovered.notes.first?.content.text, "Recoverable")
        XCTAssertNotNil(recovered.errorMessage)
        await recovered.flush()
        XCTAssertEqual(try Data(contentsOf: url), damaged)
    }

    func testLatePlaintextMetadataCannotRemoveProtectionAndBothMergeOrdersConverge() async throws {
        let secure = NoteStore(directory: try directory(), seed: false)
        let id = secure.createNote()
        secure.updateNote(id) { $0.content.text = "Do not restore this plaintext" }
        var stale = try ArchiveCodec.decode(secure.exportArchive())
        try await secure.lockNote(id, password: "protection-password")
        let protectedArchive = try secure.exportArchive()
        stale.notes[0].updatedAt = Date().addingTimeInterval(3_600)
        stale.notes[0].revisionID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
        stale.notes[0].isPinned = true
        stale.notes[0].color = .rose
        try secure.mergeArchive(ArchiveCodec.encode(stale))
        XCTAssertTrue(secure.isLocked(id))
        XCTAssertEqual(secure.notes.first?.content, NoteContent())
        XCTAssertFalse(String(decoding: try secure.exportArchive(), as: UTF8.self).contains("Do not restore this plaintext"))

        let offline = NoteStore(directory: try directory(), seed: false)
        try offline.importArchive(ArchiveCodec.encode(stale))
        try offline.mergeArchive(protectedArchive)
        XCTAssertTrue(offline.isLocked(id))
        XCTAssertEqual(offline.notes.first?.encryptedContent, secure.notes.first?.encryptedContent)
        XCTAssertEqual(offline.notes.first?.protectionRevisionID, secure.notes.first?.protectionRevisionID)
    }

    func testExplicitRemovalOutranksLateProtectedMetadataAndNewLockOutranksOldPassword() async throws {
        let store = NoteStore(directory: try directory(), seed: false)
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Keep after deliberate removal" }
        try await store.lockNote(id, password: "first-password")
        var oldProtected = try ArchiveCodec.decode(store.exportArchive())
        let lockEpoch = try XCTUnwrap(oldProtected.notes[0].protectionUpdatedAt)
        try await store.removePassword(id, password: "first-password")
        let removalEpoch = try XCTUnwrap(store.notes.first?.protectionUpdatedAt)
        XCTAssertGreaterThan(removalEpoch, lockEpoch)
        oldProtected.notes[0].updatedAt = Date().addingTimeInterval(3_600)
        oldProtected.notes[0].isPinned = true
        try store.mergeArchive(ArchiveCodec.encode(oldProtected))
        XCTAssertFalse(store.notes[0].isPasswordProtected)
        XCTAssertEqual(store.notes[0].content.text, "Keep after deliberate removal")

        let other = NoteStore(directory: try directory(), seed: false)
        try other.importArchive(ArchiveCodec.encode(oldProtected))
        try other.mergeArchive(store.exportArchive())
        XCTAssertFalse(other.notes[0].isPasswordProtected)
        XCTAssertEqual(other.notes[0].protectionRevisionID, store.notes[0].protectionRevisionID)

        try await store.lockNote(id, password: "second-password")
        XCTAssertGreaterThan(try XCTUnwrap(store.notes[0].protectionUpdatedAt), removalEpoch)
        try store.mergeArchive(ArchiveCodec.encode(oldProtected))
        try await store.unlockNote(id, password: "second-password")
        XCTAssertEqual(store.notes[0].content.text, "Keep after deliberate removal")
    }

    func testLegacyProtectedNotesDominateEpochlessPlaintextAndRemainRemovable() async throws {
        let store = NoteStore(directory: try directory(), seed: false)
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Legacy secret" }
        var plaintext = try ArchiveCodec.decode(store.exportArchive())
        try await store.lockNote(id, password: "legacy-password")
        var legacy = try ArchiveCodec.decode(store.exportArchive())
        legacy.notes[0].protectionUpdatedAt = nil
        legacy.notes[0].protectionRevisionID = nil
        plaintext.notes[0].updatedAt = Date().addingTimeInterval(3_600)
        let restored = NoteStore(directory: try directory(), seed: false)
        try restored.importArchive(ArchiveCodec.encode(legacy))
        try restored.mergeArchive(ArchiveCodec.encode(plaintext))
        XCTAssertTrue(restored.isLocked(id))
        try await restored.removePassword(id, password: "legacy-password")
        XCTAssertGreaterThan(try XCTUnwrap(restored.notes[0].protectionUpdatedAt), legacy.notes[0].updatedAt)
        try restored.mergeArchive(ArchiveCodec.encode(legacy))
        XCTAssertFalse(restored.notes[0].isPasswordProtected)
        XCTAssertEqual(restored.notes[0].content.text, "Legacy secret")
    }

    func testOrdinaryUpdatesCannotForgeProtectionVersion() async throws {
        let store = NoteStore(directory: try directory(), seed: false)
        let id = store.createNote()
        store.updateNote(id) { $0.protectionUpdatedAt = Date().addingTimeInterval(10_000); $0.protectionRevisionID = UUID() }
        XCTAssertNil(store.notes[0].protectionUpdatedAt)
        try await store.lockNote(id, password: "version-password")
        let date = store.notes[0].protectionUpdatedAt, revision = store.notes[0].protectionRevisionID
        store.updateNote(id) { $0.isPinned = true; $0.protectionUpdatedAt = nil; $0.protectionRevisionID = nil }
        XCTAssertEqual(store.notes[0].protectionUpdatedAt, date)
        XCTAssertEqual(store.notes[0].protectionRevisionID, revision)
    }
}
