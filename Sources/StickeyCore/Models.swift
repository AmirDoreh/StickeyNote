import Foundation

public enum NoteKind: String, Codable, CaseIterable, Sendable {
    case text, checklist
}

public enum NoteColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case butter, lemon, gold, peach, apricot, coral, rose, blush, pink, mauve
    case lavender, lilac, periwinkle, sky, blue, teal, mint, sage, green, olive
    case cream, sand, clay, silver, graphite
    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
    public var hex: String {
        switch self {
        case .butter: return "F7E999"
        case .lemon: return "F9E35B"
        case .gold: return "F5CB63"
        case .peach: return "F8D0AD"
        case .apricot: return "F7B879"
        case .coral: return "F49D8F"
        case .rose: return "ECA6AA"
        case .blush: return "F6D5D7"
        case .pink: return "F0BBDC"
        case .mauve: return "D8B3C9"
        case .lavender: return "D9C9F0"
        case .lilac: return "C9B4E4"
        case .periwinkle: return "BFCAEF"
        case .sky: return "C2DFF2"
        case .blue: return "A7C8EA"
        case .teal: return "A8D5D2"
        case .mint: return "C8E5D0"
        case .sage: return "D1DEC1"
        case .green: return "ADD0A5"
        case .olive: return "D2D6A4"
        case .cream: return "F3EDDD"
        case .sand: return "E7D7BC"
        case .clay: return "D5BBA7"
        case .silver: return "DFE3E7"
        case .graphite: return "B4BBC7"
        }
    }
}

public enum NoteFont: String, CaseIterable, Codable, Identifiable, Sendable {
    case system, rounded, serif, mono, avenir, helvetica, georgia, palatino
    case times, courier, menlo, baskerville, didot, futura, chalkboard, noteworthy
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        case .avenir: return "Avenir"
        case .helvetica: return "Helvetica Neue"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .times: return "Times New Roman"
        case .courier: return "Courier"
        case .menlo: return "Menlo"
        case .baskerville: return "Baskerville"
        case .didot: return "Didot"
        case .futura: return "Futura"
        case .chalkboard: return "Chalkboard"
        case .noteworthy: return "Noteworthy"
        }
    }
    public var familyName: String? {
        switch self {
        case .system, .rounded, .serif, .mono: return nil
        case .helvetica: return "HelveticaNeue"
        case .times: return "TimesNewRomanPSMT"
        case .chalkboard: return "ChalkboardSE-Regular"
        case .noteworthy: return "Noteworthy-Light"
        default: return displayName
        }
    }
}

public struct ChecklistItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var isCompleted: Bool
    public init(id: UUID = UUID(), text: String = "", isCompleted: Bool = false) {
        self.id = id; self.text = text; self.isCompleted = isCompleted
    }
}

public struct DrawingPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct DrawingStroke: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var points: [DrawingPoint]
    public var color: String
    public var width: Double
    public init(id: UUID = UUID(), points: [DrawingPoint] = [], color: String = "252525", width: Double = 3) {
        self.id = id; self.points = points; self.color = color; self.width = width
    }
}

public struct NoteContent: Codable, Equatable, Sendable {
    public var title: String
    public var text: String
    public var richText: Data?
    public var richHTML: String?
    public var items: [ChecklistItem]
    public var strokes: [DrawingStroke]
    public init(title: String = "", text: String = "", richText: Data? = nil, richHTML: String? = nil,
                items: [ChecklistItem] = [], strokes: [DrawingStroke] = []) {
        self.title = title; self.text = text; self.richText = richText; self.richHTML = richHTML
        self.items = items; self.strokes = strokes
    }
    public var plainText: String {
        ([title, text] + items.map { "\($0.isCompleted ? "☑" : "☐") \($0.text)" })
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public struct NoteSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var content: NoteContent
    public init(id: UUID = UUID(), date: Date = Date(), content: NoteContent) {
        self.id = id; self.date = date; self.content = content
    }
}

/// Only ciphertext, a public salt, and KDF parameters are serialized for a protected note.
public struct EncryptedNotePayload: Codable, Equatable, Sendable {
    public var salt: Data
    public var iterations: UInt32
    public var sealedData: Data
    public init(salt: Data, iterations: UInt32, sealedData: Data) {
        self.salt = salt; self.iterations = iterations; self.sealedData = sealedData
    }
}

public struct StickyNote: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var revisionID: UUID?
    public var kind: NoteKind
    public var content: NoteContent
    public var color: NoteColor
    public var font: NoteFont
    public var fontSize: Double
    public var groupID: UUID?
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Version only the protection transition, independently of text or metadata edits.
    public var protectionUpdatedAt: Date?
    public var protectionRevisionID: UUID?
    public var deletedAt: Date?
    public var history: [NoteSnapshot]
    public var encryptedContent: EncryptedNotePayload?
    public init(id: UUID = UUID(), revisionID: UUID? = UUID(), kind: NoteKind = .text, content: NoteContent = NoteContent(),
                color: NoteColor = .butter, font: NoteFont = .system, fontSize: Double = 18,
                groupID: UUID? = nil, isPinned: Bool = false, createdAt: Date = Date(),
                updatedAt: Date = Date(), protectionUpdatedAt: Date? = nil, protectionRevisionID: UUID? = nil,
                deletedAt: Date? = nil, history: [NoteSnapshot] = [],
                encryptedContent: EncryptedNotePayload? = nil) {
        self.id = id; self.revisionID = revisionID; self.kind = kind; self.content = content; self.color = color
        self.font = font; self.fontSize = fontSize; self.groupID = groupID; self.isPinned = isPinned
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
        self.protectionUpdatedAt = protectionUpdatedAt; self.protectionRevisionID = protectionRevisionID
        self.history = history; self.encryptedContent = encryptedContent
    }
    public var isPasswordProtected: Bool { encryptedContent != nil }
    /// Legacy encrypted notes have an implicit protection epoch. Legacy plaintext
    /// has none, so a late offline color/pin edit cannot silently remove a lock.
    public var protectionVersionDate: Date? { protectionUpdatedAt ?? (isPasswordProtected ? updatedAt : nil) }
    public func winsMerge(over other: StickyNote) -> Bool {
        // Compare the shared millisecond precision, avoiding JSON/Date rounding drift.
        let mine = protectionVersionDate.map { ($0.timeIntervalSince1970 * 1_000).rounded() }
        let theirs = other.protectionVersionDate.map { ($0.timeIntervalSince1970 * 1_000).rounded() }
        if mine != theirs {
            guard let mine else { return false }
            guard let theirs else { return true }
            return mine > theirs
        }
        let mineRevision = protectionRevisionID?.uuidString ?? ""
        let theirRevision = other.protectionRevisionID?.uuidString ?? ""
        if mineRevision != theirRevision { return mineRevision > theirRevision }
        if isPasswordProtected != other.isPasswordProtected { return isPasswordProtected }
        return updatedAt > other.updatedAt ||
            (updatedAt == other.updatedAt && (revisionID?.uuidString ?? "") >= (other.revisionID?.uuidString ?? ""))
    }
    public var displayTitle: String {
        if !content.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return content.title }
        if isPasswordProtected && content == NoteContent() { return "Locked note" }
        return kind == .checklist ? "Untitled checklist" : "Untitled note"
    }
    public var previewText: String {
        if isPasswordProtected && content == NoteContent() { return "Password protected" }
        return kind == .checklist ? content.items.map(\.text).joined(separator: "\n") : content.text
    }
    /// A safe representation for backups, sync, and widgets, even when the app is unlocked.
    public var persisted: StickyNote {
        var result = self
        if encryptedContent != nil { result.content = NoteContent(); result.history = [] }
        return result
    }
}

public struct NoteGroup: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var revisionID: UUID?
    public var name: String
    public var symbol: String
    public var updatedAt: Date
    public var deletedAt: Date?
    public init(id: UUID = UUID(), revisionID: UUID? = UUID(), name: String, symbol: String = "folder", updatedAt: Date = Date(), deletedAt: Date? = nil) {
        self.id = id; self.revisionID = revisionID; self.name = name; self.symbol = symbol; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct NoteArchive: Codable, Equatable, Sendable {
    public var version: Int
    public var notes: [StickyNote]
    public var groups: [NoteGroup]
    public var modifiedAt: Date
    public init(version: Int = 1, notes: [StickyNote], groups: [NoteGroup], modifiedAt: Date = Date()) {
        self.version = version; self.notes = notes; self.groups = groups; self.modifiedAt = modifiedAt
    }
}
