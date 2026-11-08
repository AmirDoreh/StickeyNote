import SwiftUI
import WidgetKit
import AppIntents

struct WidgetNoteEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static var defaultQuery = WidgetNoteQuery()
    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct WidgetNoteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetNoteEntity] {
        WidgetSnapshotFile.read().filter { identifiers.contains($0.id.uuidString) }
            .map { WidgetNoteEntity(id: $0.id.uuidString, title: $0.title) }
    }
    func suggestedEntities() async throws -> [WidgetNoteEntity] {
        WidgetSnapshotFile.read().map { WidgetNoteEntity(id: $0.id.uuidString, title: $0.title) }
    }
}

struct SelectNoteIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose a note"
    static var description = IntentDescription("Keep a note close by. Protected notes are never shown in widgets.")
    @Parameter(title: "Note") var note: WidgetNoteEntity?
}

struct NoteWidgetEntry: TimelineEntry {
    let date: Date
    let note: WidgetNoteSnapshot?
}

struct NoteWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NoteWidgetEntry { NoteWidgetEntry(date: Date(), note: .preview) }
    func snapshot(for configuration: SelectNoteIntent, in context: Context) async -> NoteWidgetEntry {
        entry(for: configuration)
    }
    func timeline(for configuration: SelectNoteIntent, in context: Context) async -> Timeline<NoteWidgetEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
    private func entry(for configuration: SelectNoteIntent) -> NoteWidgetEntry {
        let snapshots = WidgetSnapshotFile.read()
        let note = configuration.note.map { selection in snapshots.first { $0.id.uuidString == selection.id } } ?? snapshots.first
        return NoteWidgetEntry(date: Date(), note: note)
    }
}

struct NoteWidgetView: View {
    let entry: NoteWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        Group {
            if let note = entry.note {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.title).font(.system(.headline, design: .rounded)).lineLimit(2)
                        if note.isChecklist {
                            ForEach(Array(note.items.prefix(family == .systemLarge ? 10 : 4).enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    Text(item.text).strikethrough(item.isCompleted).lineLimit(1)
                                }
                                .font(.system(size: family == .systemSmall ? 13 : 15))
                                .opacity(item.isCompleted ? 0.5 : 1)
                            }
                        } else {
                            Text(note.text).font(.system(size: family == .systemSmall ? 14 : 16))
                                .lineLimit(family == .systemLarge ? 14 : 6)
                        }
                        Spacer(minLength: 0)
                    }
                    if !note.strokes.isEmpty {
                        Canvas { context, size in
                            for stroke in note.strokes {
                                var path = Path()
                                for (index, point) in stroke.points.enumerated() {
                                    let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
                                    if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                                }
                                context.stroke(path, with: .color(Color(widgetHex: stroke.color)),
                                               style: StrokeStyle(lineWidth: max(1, stroke.width * 0.5), lineCap: .round, lineJoin: .round))
                            }
                        }
                        .accessibilityLabel("Drawing")
                    }
                }
                .foregroundStyle(showsBackground ? Color(widgetHex: "282B26") : Color.primary)
                .widgetURL(URL(string: "stickeynote://note/\(note.id.uuidString)"))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "note.text").font(.title2)
                    Text("Your ideas, close by.").font(.headline)
                    Text("Open StickeyNote and choose a note to display.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .widgetURL(URL(string: "stickeynote://notes"))
            }
        }
        .containerBackground(for: .widget) { Color(widgetHex: entry.note?.color ?? "F7E999") }
    }
}

@main
struct StickeyNoteWidget: Widget {
    let kind = "StickeyNoteWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectNoteIntent.self, provider: NoteWidgetProvider()) { entry in
            NoteWidgetView(entry: entry)
        }
        .configurationDisplayName("StickeyNote")
        .description("Keep a note on your Home Screen, desktop, or in CarPlay.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private extension Color {
    init(widgetHex: String) {
        let number = UInt64(widgetHex, radix: 16) ?? 0xF7E999
        self.init(red: Double((number >> 16) & 255) / 255,
                  green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}
