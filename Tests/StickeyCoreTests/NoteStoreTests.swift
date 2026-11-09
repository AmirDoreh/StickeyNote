import XCTest
@testable import StickeyCore

@MainActor
final class NoteStoreTests: XCTestCase {
    private var directories: [URL] = []
    private var preferenceSuites: [String] = []
    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "StickeyCoreTests.autoLock.\(UUID().uuidString)"
        preferenceSuites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StickeyCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }
    override func tearDown() async throws {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
        for suite in preferenceSuites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        preferenceSuites = []
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

    func testAutoLockPreferenceDefaultsToTwoMinutesAndPersistsOnDevice() throws {
        let suite = "StickeyCoreTests.autoLock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NoteStore(directory: try directory(), seed: false, defaults: defaults)
        XCTAssertEqual(store.autoLockSeconds, 120)
        store.autoLockSeconds = 300
        let reopened = NoteStore(directory: try directory(), seed: false, defaults: defaults)
        XCTAssertEqual(reopened.autoLockSeconds, 300)
        store.autoLockSeconds = .infinity
        XCTAssertEqual(store.autoLockSeconds, 120)
        XCTAssertEqual(NoteStore.autoLockOptions, [30, 60, 120, 300, 600, 900])
    }

    func testPINValidationEncryptionAndIncorrectPIN() async throws {
        let store = NoteStore(directory: try directory(), seed: false, defaults: try isolatedDefaults())
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Only after a PIN" }
        for invalid in ["", "123", "1234567890123", "12a4", "１２３４", "1234 "] {
            do { try await store.lockNote(id, pin: invalid); XCTFail("Invalid PIN must fail") }
            catch { XCTAssertEqual(error as? NoteSecurityError, .invalidPIN) }
        }
        do { try await store.lockNote(id, password: "short"); XCTFail("Password validation remains unchanged") }
        catch { XCTAssertEqual(error as? NoteSecurityError, .passwordTooShort) }
        try await store.lockNote(id, pin: "0420")
        XCTAssertTrue(store.isLocked(id))
        XCTAssertFalse(String(decoding: try store.exportArchive(), as: UTF8.self).contains("Only after a PIN"))
        do { try await store.unlockNote(id, password: "0421"); XCTFail("Incorrect PIN must fail") }
        catch { XCTAssertEqual(error as? NoteSecurityError, .incorrectPassword) }
        XCTAssertTrue(store.isLocked(id))
        try await store.unlockNote(id, password: "0420")
        XCTAssertEqual(store.notes.first?.content.text, "Only after a PIN")
    }

    func testAutoLockExpiresAtTwoMinutesAndRetainsLatestEncryptedEdits() async throws {
        let store = NoteStore(directory: try directory(), seed: false, defaults: try isolatedDefaults())
        var now = ContinuousClock.now
        store.autoLockNow = { now }
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Original secret" }
        try await store.lockNote(id, pin: "1234")
        try await store.unlockNote(id, password: "1234")
        now = now.advanced(by: .seconds(119))
        store.relockExpiredNotes()
        XCTAssertFalse(store.isLocked(id))
        store.updateNote(id) { $0.content.text = "Latest secret" }
        now = now.advanced(by: .seconds(1))
        store.relockExpiredNotes()
        XCTAssertTrue(store.isLocked(id))
        XCTAssertEqual(store.notes.first?.content, NoteContent())
        XCTAssertTrue(store.notes.first?.history.isEmpty == true)
        XCTAssertFalse(String(decoding: try store.exportArchive(), as: UTF8.self).contains("Latest secret"))
        try await store.unlockNote(id, password: "1234")
        XCTAssertEqual(store.notes.first?.content.text, "Latest secret")
        now = now.advanced(by: .seconds(120))
        store.updateNote(id) { $0.content.text = "An overdue editor write" }
        XCTAssertTrue(store.isLocked(id))
        try await store.unlockNote(id, password: "1234")
        XCTAssertEqual(store.notes.first?.content.text, "Latest secret")
    }

    func testChangingAutoLockUsesOriginalAuthenticationTime() async throws {
        let suite = "StickeyCoreTests.autoLock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NoteStore(directory: try directory(), seed: false, defaults: defaults)
        var now = ContinuousClock.now
        store.autoLockNow = { now }
        let id = store.createNote()
        try await store.lockNote(id, pin: "1234")
        try await store.unlockNote(id, password: "1234")
        now = now.advanced(by: .seconds(90))
        store.autoLockSeconds = 300
        now = now.advanced(by: .seconds(209))
        store.relockExpiredNotes()
        XCTAssertFalse(store.isLocked(id))
        now = now.advanced(by: .seconds(1))
        store.relockExpiredNotes()
        XCTAssertTrue(store.isLocked(id))
        try await store.unlockNote(id, password: "1234")
        now = now.advanced(by: .seconds(61))
        store.autoLockSeconds = 60
        XCTAssertTrue(store.isLocked(id), "Shortening below elapsed time must lock immediately")
        try await store.unlockNote(id, password: "1234")
        now = now.advanced(by: .seconds(61))
        store.autoLockSeconds = 300
        XCTAssertTrue(store.isLocked(id), "Extending the setting cannot revive an already expired session")
    }

    func testProtectedDuplicateInheritsRemainingAutoLockTime() async throws {
        let store = NoteStore(directory: try directory(), seed: false, defaults: try isolatedDefaults())
        var now = ContinuousClock.now
        store.autoLockNow = { now }
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Private copy" }
        try await store.lockNote(id, pin: "1234")
        try await store.unlockNote(id, password: "1234")
        now = now.advanced(by: .seconds(119))
        let copy = try XCTUnwrap(store.duplicateNote(id))
        XCTAssertFalse(store.isLocked(copy))
        now = now.advanced(by: .seconds(1))
        store.relockExpiredNotes()
        XCTAssertTrue(store.isLocked(id))
        XCTAssertTrue(store.isLocked(copy))
        try await store.unlockNote(copy, password: "1234")
        XCTAssertEqual(store.notes.first(where: { $0.id == copy })?.content.text, "Private copy")
    }

    func testScheduledAutoLockActuallyFiresWithoutInteraction() async throws {
        let suite = "StickeyCoreTests.autoLock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NoteStore(directory: try directory(), seed: false, defaults: defaults)
        var advance: Double = 0
        store.autoLockNow = { ContinuousClock.now.advanced(by: .seconds(advance)) }
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Hide without interaction" }
        try await store.lockNote(id, pin: "1234")
        try await store.unlockNote(id, password: "1234")
        advance = 119.95
        store.autoLockSeconds = 300
        store.autoLockSeconds = 120
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !store.isLocked(id), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.isLocked(id))
        XCTAssertEqual(store.notes.first?.content, NoteContent())
    }

    func testRelockRejectsCredentialRetrievedByAnEarlierBiometricPrompt() async throws {
        let store = NoteStore(directory: try directory(), seed: false, defaults: try isolatedDefaults())
        let id = store.createNote()
        try await store.lockNote(id, pin: "1234")
        let token = store.securityGenerationToken(for: id)
        store.relockAll()
        do {
            try await store.unlockNote(id, password: "1234", expectedGeneration: token)
            XCTFail("A biometric result from before a relock must not reopen the note")
        } catch { XCTAssertEqual(error as? NoteSecurityError, .locked) }
        XCTAssertTrue(store.isLocked(id))
        try await store.unlockNote(id, password: "1234", expectedGeneration: store.securityGenerationToken(for: id))
        XCTAssertFalse(store.isLocked(id))
    }

    func testRemovingProtectionCancelsTheAutoLockSession() async throws {
        let store = NoteStore(directory: try directory(), seed: false, defaults: try isolatedDefaults())
        var now = ContinuousClock.now
        store.autoLockNow = { now }
        let id = store.createNote()
        store.updateNote(id) { $0.content.text = "Deliberately unprotected" }
        try await store.lockNote(id, pin: "1234")
        try await store.removePassword(id, password: "1234")
        now = now.advanced(by: .seconds(120))
        store.relockExpiredNotes()
        XCTAssertFalse(store.isLocked(id))
        XCTAssertFalse(store.notes[0].isPasswordProtected)
        XCTAssertEqual(store.notes[0].content.text, "Deliberately unprotected")
    }

    func testAppleCredentialMetadataSurvivesEditsPersistenceAndImport() async throws {
        let location = try directory()
        let store = NoteStore(directory: location, seed: false, defaults: try isolatedDefaults())
        let id = store.createNote(), credentialID = UUID()
        let secret = "generated-apple-credential-for-testing-001"
        store.updateNote(id) { $0.content = NoteContent(title: "Private Apple title", text: "Private Apple body") }
        try await store.lockNoteWithAppleCredential(id, credential: secret, credentialID: credentialID)
        XCTAssertTrue(store.isLocked(id))
        XCTAssertTrue(store.notes[0].usesAppleAuthentication)
        XCTAssertEqual(store.notes[0].encryptedContent?.credentialID, credentialID)
        let archive = try store.exportArchive()
        let text = String(decoding: archive, as: UTF8.self)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("Private Apple"))
        let imported = NoteStore(directory: try directory(), seed: false, defaults: try isolatedDefaults())
        try imported.importArchive(archive)
        XCTAssertEqual(imported.notes[0].encryptedContent?.credentialKind, "apple")
        XCTAssertEqual(imported.notes[0].encryptedContent?.credentialID, credentialID)
        try await store.unlockNote(id, password: secret)
        store.updateNote(id) { $0.content.text = "Latest Apple edit" }
        await store.flush()
        XCTAssertEqual(store.notes[0].encryptedContent?.credentialID, credentialID)
        let reopened = NoteStore(directory: location, seed: false, defaults: try isolatedDefaults())
        XCTAssertTrue(reopened.notes[0].usesAppleAuthentication)
        XCTAssertEqual(reopened.notes[0].encryptedContent?.credentialID, credentialID)
        try await reopened.unlockNote(id, password: secret)
        XCTAssertEqual(reopened.notes[0].content.text, "Latest Apple edit")
    }

    func testAppleProtectedDuplicateRetainsCredentialReferenceAndCiphertextBinding() async throws {
        let store = NoteStore(directory: try directory(), seed: false, defaults: try isolatedDefaults())
        let id = store.createNote(), credentialID = UUID()
        let secret = "generated-apple-credential-for-testing-002"
        store.updateNote(id) { $0.content.text = "Apple private duplicate" }
        try await store.lockNoteWithAppleCredential(id, credential: secret, credentialID: credentialID)
        try await store.unlockNote(id, password: secret)
        let duplicate = try XCTUnwrap(store.duplicateNote(id))
        XCTAssertTrue(store.notes.first(where: { $0.id == duplicate })?.usesAppleAuthentication == true)
        XCTAssertEqual(store.notes.first(where: { $0.id == duplicate })?.encryptedContent?.credentialID, credentialID)
        store.relockAll()
        try await store.unlockNote(duplicate, password: secret)
        XCTAssertEqual(store.notes.first(where: { $0.id == duplicate })?.content.text, "Apple private duplicate")
        var tampered = try ArchiveCodec.decode(store.exportArchive())
        let originalPayload = try XCTUnwrap(tampered.notes.first(where: { $0.id == id })?.encryptedContent)
        let copiedIndex = try XCTUnwrap(tampered.notes.firstIndex(where: { $0.id == duplicate }))
        tampered.notes[copiedIndex].encryptedContent = originalPayload
        let other = NoteStore(directory: try directory(), seed: false, defaults: try isolatedDefaults())
        try other.importArchive(ArchiveCodec.encode(tampered))
        do { try await other.unlockNote(duplicate, password: secret); XCTFail("Copied ciphertext must remain bound to its note ID") }
        catch { XCTAssertEqual(error as? NoteSecurityError, .incorrectPassword) }
    }

    func testLegacyConversionKeepsHistoryEncryptedAndRequiresCurrentAuthentication() async throws {
        let location = try directory()
        let store = NoteStore(directory: location, seed: false, defaults: try isolatedDefaults())
        let id = store.createNote(), credentialID = UUID()
        let secret = "generated-apple-credential-for-testing-003"
        store.updateNote(id) { $0.content.text = "Legacy private history" }
        store.updateNote(id) { $0.content.text = "Legacy private latest" }
        try await store.lockNote(id, pin: "0412")
        XCTAssertFalse(store.notes[0].usesAppleAuthentication)
        let oldEpoch = try XCTUnwrap(store.notes[0].protectionUpdatedAt)
        do {
            try await store.convertToAppleAuthentication(id, credential: secret, credentialID: credentialID)
            XCTFail("A locked legacy note cannot be converted")
        } catch { XCTAssertEqual(error as? NoteSecurityError, .locked) }
        try await store.unlockNote(id, password: "0412")
        try await store.convertToAppleAuthentication(id, credential: secret, credentialID: credentialID,
            expectedGeneration: store.securityGenerationToken(for: id))
        XCTAssertTrue(store.isLocked(id))
        XCTAssertGreaterThan(try XCTUnwrap(store.notes[0].protectionUpdatedAt), oldEpoch)
        for filename in ["notes.json", "notes.backup.json"] {
            let persisted = try String(contentsOf: location.appendingPathComponent(filename), encoding: .utf8)
            XCTAssertFalse(persisted.contains("Legacy private"))
            XCTAssertFalse(persisted.contains(secret))
        }
        do { try await store.unlockNote(id, password: "0412"); XCTFail("The old PIN must no longer decrypt a converted note") }
        catch { XCTAssertEqual(error as? NoteSecurityError, .incorrectPassword) }
        try await store.unlockNote(id, password: secret)
        XCTAssertEqual(store.notes[0].content.text, "Legacy private latest")
        XCTAssertTrue(store.notes[0].history.contains { $0.content.text == "Legacy private history" })
    }

    func testAppleConversionAndRemovalRejectStaleAuthentication() async throws {
        let store = NoteStore(directory: try directory(), seed: false, defaults: try isolatedDefaults())
        let id = store.createNote(), credentialID = UUID()
        let secret = "generated-apple-credential-for-testing-004"
        store.updateNote(id) { $0.content.text = "Retain on cancelled conversion" }
        try await store.lockNote(id, pin: "1234")
        try await store.unlockNote(id, password: "1234")
        let token = store.securityGenerationToken(for: id)
        let conversion = Task { try await store.convertToAppleAuthentication(id, credential: secret,
            credentialID: credentialID, expectedGeneration: token) }
        await Task.yield()
        store.relockAll()
        do { try await conversion.value; XCTFail("Relock must cancel an in-flight conversion") }
        catch { XCTAssertEqual(error as? NoteSecurityError, .locked) }
        XCTAssertFalse(store.notes[0].usesAppleAuthentication)
        XCTAssertTrue(store.isLocked(id))
        do { try await store.removePassword(id, password: "1234", expectedGeneration: token); XCTFail("Stale auth must not remove protection") }
        catch { XCTAssertEqual(error as? NoteSecurityError, .locked) }
        try await store.unlockNote(id, password: "1234")
        XCTAssertEqual(store.notes[0].content.text, "Retain on cancelled conversion")
    }

    func testCredentialMetadataValidatesPairAndLegacyEncodingRemainsCompatible() throws {
        let legacy = EncryptedNotePayload(salt: Data(repeating: 0, count: 16), iterations: 600_000,
                                          sealedData: Data(repeating: 0, count: 32))
        let note = StickyNote(encryptedContent: legacy)
        let original = NoteArchive(notes: [note], groups: [])
        let encoded = try ArchiveCodec.encode(original)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("credentialKind"))
        XCTAssertEqual(try ArchiveCodec.decode(encoded).notes[0].encryptedContent, legacy)
        for (kind, id) in [("apple", nil as UUID?), ("unexpected", UUID()), (nil as String?, UUID())] {
            var archive = original
            archive.notes[0].encryptedContent?.credentialKind = kind
            archive.notes[0].encryptedContent?.credentialID = id
            XCTAssertThrowsError(try ArchiveCodec.decode(ArchiveCodec.encode(archive))) { error in
                XCTAssertEqual(error as? NoteSecurityError, .invalidArchive)
            }
        }
    }

}
