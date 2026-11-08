import Foundation
import WidgetKit
import StickeyCore

enum WidgetSnapshotWriter {
    /// Call after notes change. The caller can debounce ordinary text edits;
    /// call immediately when a note is locked or removed to clear old previews.
    @MainActor
    static func update(notes: [StickyNote]) {
        guard let url = WidgetSnapshotFile.url else { return }
        let snapshots = notes.filter { !$0.isPasswordProtected && $0.deletedAt == nil }
            .sorted { $0.isPinned != $1.isPinned ? $0.isPinned : $0.updatedAt > $1.updatedAt }
            .map { note in
                WidgetNoteSnapshot(id: note.id, title: String(note.displayTitle.prefix(160)),
                                   text: String(note.content.text.prefix(4_000)), color: note.color.hex,
                                   items: note.content.items.prefix(30).map {
                    WidgetNoteSnapshot.Item(text: String($0.text.prefix(240)), isCompleted: $0.isCompleted)
                }, strokes: note.content.strokes.suffix(150).map { stroke in
                    // Keep the entire shape while reducing widget rendering work.
                    let strideSize = max(1, stroke.points.count / 400)
                    let points = stride(from: 0, to: stroke.points.count, by: strideSize).map { index in
                        WidgetNoteSnapshot.Stroke.Point(x: stroke.points[index].x, y: stroke.points[index].y)
                    }
                    return WidgetNoteSnapshot.Stroke(points: points, color: stroke.color, width: stroke.width)
                }, isChecklist: note.kind == .checklist, updatedAt: note.updatedAt)
            }
        do {
            let data = try JSONEncoder().encode(snapshots)
            if let previous = try? Data(contentsOf: url), previous == data { return }
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            WidgetCenter.shared.reloadTimelines(ofKind: "StickeyNoteWidget")
        } catch {
            // Never leave a stale, potentially sensitive widget snapshot behind.
            try? FileManager.default.removeItem(at: url)
            WidgetCenter.shared.reloadTimelines(ofKind: "StickeyNoteWidget")
        }
    }
}
