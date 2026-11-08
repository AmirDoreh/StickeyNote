import SwiftUI
import StickeyCore

@main
struct StickeyNoteApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(StickeyAppDelegate.self) private var appDelegate
    #endif
    @State private var store = NoteStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup("Stickey Notes", id: "main") {
            BoardView(store: store)
                .tint(Palette.ink)
                .preferredColorScheme(.light)
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 560)
                #endif
                .onOpenURL { url in
                    guard url.scheme == "stickeynote", url.host == "note", let id = UUID(uuidString: url.lastPathComponent), store.notes.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return }
                    store.selectedNoteID = id
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { store.relockAll(); Task { await store.flush() } }
                }
                #if os(macOS)
                .onAppear { appDelegate.store = store; FloatingNoteWindows.shared.configure(store: store); FloatingNoteWindows.shared.restore() }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { let id = store.createNote(); FloatingNoteWindows.shared.openMainNote?(id) }.keyboardShortcut("n")
                Button("New Checklist") { let id = store.createNote(kind: .checklist); FloatingNoteWindows.shared.openMainNote?(id) }.keyboardShortcut("t")
            }
            CommandMenu("Desktop") {
                Button("Keep selected note on desktop") { if let id = store.selectedNoteID { FloatingNoteWindows.shared.pin(id) } }.keyboardShortcut("d", modifiers: [.command, .shift]).disabled(store.selectedNoteID == nil)
                Divider()
                Button("Show desktop notes") { FloatingNoteWindows.shared.showAll() }
                Button("Hide desktop notes") { FloatingNoteWindows.shared.hideAll() }
            }
        }
        #endif
        #if os(macOS)
        MenuBarExtra("Stickey Notes", systemImage: "note.text") { DesktopMenu(store: store) }.menuBarExtraStyle(.menu)
        #endif
    }
}
