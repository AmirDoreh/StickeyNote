import Foundation

/// Compile this file into both the app and widget extension. The snapshot
/// deliberately contains no password-protected notes, keys, or history.
struct WidgetNoteSnapshot: Codable, Identifiable, Sendable {
    struct Item: Codable, Sendable {
        var text: String
        var isCompleted: Bool
    }
    struct Stroke: Codable, Sendable {
        struct Point: Codable, Sendable { var x: Double; var y: Double }
        var points: [Point]
        var color: String
        var width: Double
    }
    var id: UUID
    var title: String
    var text: String
    var color: String
    var items: [Item]
    var strokes: [Stroke]
    var isChecklist: Bool
    var updatedAt: Date

    static var preview: WidgetNoteSnapshot {
        WidgetNoteSnapshot(id: UUID(), title: "A little reminder", text: "Make room for your next good idea.",
                           color: "F7E999", items: [], strokes: [], isChecklist: false, updatedAt: Date())
    }
}

enum WidgetSnapshotFile {
    static let appGroup = "group.com.stickeynote.app"
    static let filename = "widget-notes.json"
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }
    static func read() -> [WidgetNoteSnapshot] {
        guard let url, let data = try? Data(contentsOf: url), data.count < 20_000_000 else { return [] }
        return (try? JSONDecoder().decode([WidgetNoteSnapshot].self, from: data)) ?? []
    }
}
