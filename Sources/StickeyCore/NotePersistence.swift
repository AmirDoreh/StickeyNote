import Foundation

public enum ArchiveCodec {
    public static func encode(_ archive: NoteArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(archive)
    }
    public static func decode(_ data: Data) throws -> NoteArchive {
        guard data.count <= 100_000_000 else { throw NoteSecurityError.invalidArchive }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive: NoteArchive
        do { archive = try decoder.decode(NoteArchive.self, from: data) }
        catch { throw NoteSecurityError.invalidArchive }
        guard archive.version == 1 else { throw NoteSecurityError.newerArchive }
        guard Set(archive.notes.map(\.id)).count == archive.notes.count,
              Set(archive.groups.map(\.id)).count == archive.groups.count,
              archive.notes.allSatisfy({ $0.fontSize.isFinite && (8...96).contains($0.fontSize) }) else {
            throw NoteSecurityError.invalidArchive
        }
        return archive
    }
}

actor NotePersistence {
    let directory: URL
    private var lastRevision: UInt64 = 0
    init(directory: URL) { self.directory = directory }

    func write(_ data: Data, revision: UInt64, replaceBackup: Bool) throws {
        guard revision >= lastRevision else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let primary = directory.appendingPathComponent("notes.json")
        let backup = directory.appendingPathComponent("notes.backup.json")
        // Keep the last valid archive. When introducing a password, replace both copies
        // with the sanitized archive so a recovery file cannot expose the old content.
        if !replaceBackup, let previous = try? Data(contentsOf: primary),
           (try? ArchiveCodec.decode(previous)) != nil {
            try previous.write(to: backup, options: .atomic)
        }
        try data.write(to: primary, options: .atomic)
        if replaceBackup || !manager.fileExists(atPath: backup.path) {
            try data.write(to: backup, options: .atomic)
        }
        #if os(iOS)
        try? manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: primary.path)
        try? manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: backup.path)
        #endif
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: primary.path)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        lastRevision = revision
    }
}
