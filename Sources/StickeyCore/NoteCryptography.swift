import Foundation
import CryptoKit
import CommonCrypto
import Security

public enum NoteSecurityError: LocalizedError, Equatable {
    case passwordTooShort, invalidPIN, incorrectPassword, locked, unavailable, invalidArchive, newerArchive
    public var errorDescription: String? {
        switch self {
        case .passwordTooShort: return "Use a password with at least 8 characters."
        case .invalidPIN: return "Use a PIN with 4 to 12 digits."
        case .incorrectPassword: return "That PIN or password didn’t unlock this note."
        case .locked: return "Unlock the note before editing it."
        case .unavailable: return "The note could not be protected. Please try again."
        case .invalidArchive: return "This file is not a valid StickeyNote backup."
        case .newerArchive: return "This backup was created with a newer version of StickeyNote."
        }
    }
}

struct PrivateNoteBody: Codable {
    var content: NoteContent
    var history: [NoteSnapshot]
}

enum NoteCryptography {
    static let iterations: UInt32 = 600_000
    static func randomSalt() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NoteSecurityError.unavailable
        }
        return Data(bytes)
    }
    static func key(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard salt.count == 16, iterations >= 100_000, iterations <= 2_000_000 else {
            throw NoteSecurityError.invalidArchive
        }
        let passwordData = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let result = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), passwordData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &derived, derived.count)
            }
        }
        guard result == kCCSuccess else { throw NoteSecurityError.unavailable }
        defer { _ = derived.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        return SymmetricKey(data: derived)
    }
    static func encrypt(_ note: StickyNote, key: SymmetricKey, salt: Data, iterations: UInt32) throws -> EncryptedNotePayload {
        let body = PrivateNoteBody(content: note.content, history: note.history)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(body)
        let sealed = try AES.GCM.seal(data, using: key, authenticating: Data(note.id.uuidString.utf8))
        guard let combined = sealed.combined else { throw NoteSecurityError.unavailable }
        return EncryptedNotePayload(salt: salt, iterations: iterations, sealedData: combined,
                                    credentialKind: note.encryptedContent?.credentialKind,
                                    credentialID: note.encryptedContent?.credentialID)
    }
    static func decrypt(_ payload: EncryptedNotePayload, noteID: UUID, key: SymmetricKey) throws -> PrivateNoteBody {
        do {
            let box = try AES.GCM.SealedBox(combined: payload.sealedData)
            let plaintext = try AES.GCM.open(box, using: key, authenticating: Data(noteID.uuidString.utf8))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try decoder.decode(PrivateNoteBody.self, from: plaintext)
        } catch { throw NoteSecurityError.incorrectPassword }
    }
}
