import Foundation

extension NoteStore {
    static func samples() -> NoteArchive {
        let personal = NoteGroup(name: "Personal", symbol: "sun.max")
        let work = NoteGroup(name: "Work", symbol: "briefcase")
        let ideas = NoteGroup(name: "Ideas", symbol: "lightbulb")
        let now = Date()
        let welcome = StickyNote(content: NoteContent(title: "A little space for big ideas.",
            text: "A thought. A plan. Something you don’t want to forget.\n\nMake a note, pick a color, and make room for what matters. Everything saves as you go."),
            color: .butter, groupID: personal.id, isPinned: true, createdAt: now.addingTimeInterval(-600), updatedAt: now)
        let today = StickyNote(kind: .checklist, content: NoteContent(title: "A good kind of day", items: [
            ChecklistItem(text: "Make a fresh cup of coffee", isCompleted: true),
            ChecklistItem(text: "Make space for a little focus"),
            ChecklistItem(text: "Take a walk outside"),
            ChecklistItem(text: "Write down one good idea")
        ]), color: .mint, groupID: personal.id, createdAt: now.addingTimeInterval(-500), updatedAt: now.addingTimeInterval(-60))
        let project = StickyNote(content: NoteContent(title: "Less, but better.",
            text: "For the next thing we make:\n\n• Start with what people need.\n• Keep the useful parts simple.\n• Leave a little room for delight.\n\nClarity is a feature."),
            color: .lavender, groupID: work.id, createdAt: now.addingTimeInterval(-400), updatedAt: now.addingTimeInterval(-120))
        let weekend = StickyNote(kind: .checklist, content: NoteContent(title: "Weekend, loosely planned", items: [
            ChecklistItem(text: "Visit the farmers’ market"),
            ChecklistItem(text: "Find a new book"),
            ChecklistItem(text: "Cook something slow"),
            ChecklistItem(text: "Leave the afternoon open")
        ]), color: .peach, groupID: personal.id, createdAt: now.addingTimeInterval(-300), updatedAt: now.addingTimeInterval(-180))
        let idea = StickyNote(content: NoteContent(title: "What if…", text: "The best ideas rarely arrive at your desk.\n\nKeep this little corner for the ones that find you along the way.", strokes: [
            DrawingStroke(points: [DrawingPoint(x: 0.12, y: 0.78), DrawingPoint(x: 0.24, y: 0.75), DrawingPoint(x: 0.38, y: 0.79), DrawingPoint(x: 0.52, y: 0.76), DrawingPoint(x: 0.68, y: 0.78)], color: "486960", width: 2.5)
        ]), color: .sky, groupID: ideas.id, createdAt: now.addingTimeInterval(-200), updatedAt: now.addingTimeInterval(-240))
        let shortcuts = StickyNote(content: NoteContent(title: "Small shortcuts, big help", text: "⌘ N  A fresh note\n⌘ T  A new checklist\n⌘ F  Find a thought\n\nUse the palette to change a color. Pin your favorites. Browse history to bring an earlier idea back."), color: .blush,
            createdAt: now.addingTimeInterval(-100), updatedAt: now.addingTimeInterval(-300))
        return NoteArchive(notes: [welcome, today, project, weekend, idea, shortcuts], groups: [personal, work, ideas])
    }
}
