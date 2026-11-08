import SwiftUI
import UniformTypeIdentifiers
import StickeyCore

struct NoteDetailView: View {
    @Bindable var store: NoteStore
    let noteID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = "write"
    @State private var showQR = false
    @State private var showHistory = false
    @State private var showLock = false
    @State private var showAppearance = false
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var export = false
    private var note: StickyNote? { store.notes.first { $0.id == noteID } }
    var body: some View {
        Group {
            if let note {
                VStack(spacing: 0) {
                    topBar(note)
                    if store.isLocked(noteID) { lockedContent }
                    else {
                        VStack(spacing: 0) {
                            titleField(note)
                            if note.kind == .checklist {
                                ChecklistEditor(items: contentBinding(\.items, fallback: []), fontSize: note.fontSize, font: note.font).padding(.horizontal, 22).padding(.bottom, 20)
                            } else if tab == "draw" {
                                DrawingEditor(strokes: contentBinding(\.strokes, fallback: []), backgroundText: note.content.text, font: note.font, fontSize: note.fontSize).padding(20)
                            } else {
                                RichEditorPanel(text: contentBinding(\.text, fallback: ""), richText: contentBinding(\.richText, fallback: nil), richHTML: contentBinding(\.richHTML, fallback: nil), font: note.font, fontSize: note.fontSize).padding(.horizontal, 22).padding(.bottom, 15)
                                if !note.content.strokes.isEmpty {
                                    Button { tab = "draw" } label: { DrawingPreview(strokes: note.content.strokes).frame(height: 110).padding(.horizontal, 24) }.buttonStyle(.plain).help("Edit drawing")
                                }
                            }
                        }.background(Color(hex: note.color.hex).opacity(0.8))
                    }
                    bottomBar(note)
                }.background(Palette.paper).foregroundStyle(Palette.ink)
                    .sheet(isPresented: $showQR) { QRCodeView(text: note.content.plainText) }
                    .sheet(isPresented: $showHistory) { HistoryView(store: store, noteID: noteID) }
                    .sheet(isPresented: $showLock) { PasswordSheet(store: store, noteID: noteID) }
                    .popover(isPresented: $showAppearance) { appearance(note).padding(22).frame(width: 295) }
                    .fileExporter(isPresented: $export, document: PlainTextDocument(text: note.content.plainText), contentType: .plainText, defaultFilename: note.displayTitle + ".txt") { result in if case let .failure(e) = result { error = e.localizedDescription } }
            } else { EmptyState(symbol: "note.text", title: "Note unavailable", message: "This note may have been removed on another device.") }
        }
        #if os(macOS)
        .frame(minWidth: 590, idealWidth: 700, minHeight: 590, idealHeight: 700)
        #endif
        .alert("Couldn’t complete that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { showQR = false; showHistory = false; showLock = false; password = "" }
        }
    }
    private func topBar(_ note: StickyNote) -> some View {
        HStack(spacing: 8) {
            IconButton(symbol: "xmark", help: "Close note") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            Rectangle().fill(Palette.line).frame(width: 1, height: 18)
            Menu {
                Button("No group") { store.updateNote(noteID) { $0.groupID = nil } }
                ForEach(store.groups) { group in Button(group.name) { store.updateNote(noteID) { $0.groupID = group.id } } }
            } label: { Label(store.groups.first { $0.id == note.groupID }?.name ?? "No group", systemImage: "folder").font(.system(size: 12)) }.menuStyle(.borderlessButton).fixedSize()
            Spacer()
            IconButton(symbol: note.isPinned ? "pin.fill" : "pin", help: note.isPinned ? "Unpin note" : "Pin note") { store.updateNote(noteID) { $0.isPinned.toggle() } }
            if !store.isLocked(noteID) {
                #if os(macOS)
                IconButton(symbol: "macwindow.on.rectangle", help: "Keep on desktop") { FloatingNoteWindows.shared.pin(noteID) }
                #endif
                IconButton(symbol: "paintpalette", help: "Note appearance") { showAppearance = true }
                Menu {
                    Button("Show QR code", systemImage: "qrcode") { showQR = true }
                    ShareLink(item: note.content.plainText) { Label("Share note", systemImage: "square.and.arrow.up") }
                    Button("Export as text", systemImage: "doc.text") { export = true }
                    #if os(macOS)
                    Button("Keep on desktop", systemImage: "macwindow.on.rectangle") { FloatingNoteWindows.shared.pin(noteID) }
                    #endif
                    Button("Version history", systemImage: "clock.arrow.circlepath") { showHistory = true }
                    Button(note.isPasswordProtected ? "Password settings" : "Protect with password", systemImage: "lock") { showLock = true }
                    if note.isPasswordProtected { Button("Lock now", systemImage: "lock.fill") { store.relockNote(noteID) } }
                    Button("Duplicate note", systemImage: "doc.on.doc") { _ = store.duplicateNote(noteID) }
                    Divider()
                    if note.deletedAt == nil { Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) { store.deleteNote(noteID); dismiss() } }
                    else { Button("Restore note", systemImage: "arrow.uturn.backward") { store.restoreNote(noteID); dismiss() } }
                } label: { Image(systemName: "ellipsis").font(.system(size: 17)).frame(width: 28, height: 30) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Note actions")
            }
        }.padding(.horizontal, 15).padding(.vertical, 12)
    }
    private func titleField(_ note: StickyNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Untitled note", text: contentBinding(\.title, fallback: ""), axis: .vertical).font(.system(size: 29, weight: .semibold, design: .rounded)).textFieldStyle(.plain).lineLimit(1...3).accessibilityLabel("Note title")
            if note.kind == .text {
                HStack(spacing: 18) {
                    Button { tab = "write" } label: { Label("Write", systemImage: "text.alignleft").font(.system(size: 12, weight: tab == "write" ? .semibold : .regular)) }.buttonStyle(.plain).opacity(tab == "write" ? 1 : 0.45)
                    Button { tab = "draw" } label: { Label("Draw", systemImage: "pencil.tip").font(.system(size: 12, weight: tab == "draw" ? .semibold : .regular)) }.buttonStyle(.plain).opacity(tab == "draw" ? 1 : 0.45)
                    Spacer()
                }
            } else {
                Text("\(note.content.items.filter(\.isCompleted).count) of \(note.content.items.count) completed").font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.5))
            }
        }.padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 20)
    }
    private var lockedContent: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Palette.secondary)
            Text("Just for you.").font(.system(size: 28, weight: .medium, design: .serif))
            Text("Enter your password to open this note.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder).frame(maxWidth: 280).onSubmit(unlock)
            Button(action: unlock) { if busy { ProgressView().controlSize(.small) } else { Text("Unlock note") } }.buttonStyle(PillButtonStyle(filled: true)).disabled(password.isEmpty || busy)
            if BiometricNoteKeys.hasCredential(noteID: noteID) { Button("Use Face ID / Touch ID") { biometricUnlock() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary).disabled(busy) }
            Spacer()
        }.frame(maxWidth: .infinity).padding(30)
    }
    private func bottomBar(_ note: StickyNote) -> some View {
        HStack(spacing: 6) {
            Image(systemName: note.isPasswordProtected ? "lock.shield" : "checkmark.circle").font(.system(size: 11))
            Text(store.saveStatus).font(.system(size: 11))
            Spacer()
            if !store.isLocked(noteID) { Text("\(note.content.text.split { $0.isWhitespace || $0.isNewline }.count) words").font(.system(size: 11)) }
            Text("·").padding(.horizontal, 4)
            Text(note.updatedAt, format: .dateTime.month(.abbreviated).day()).font(.system(size: 11))
        }.foregroundStyle(Palette.secondary).padding(16)
    }
    private func appearance(_ note: StickyNote) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make it yours").font(.system(size: 19, weight: .semibold, design: .rounded))
            Text("NOTE COLOR").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                ForEach(NoteColor.allCases) { color in
                    Button { store.updateNote(noteID) { $0.color = color } } label: {
                        Circle().fill(Color(hex: color.hex)).frame(width: 31, height: 31).overlay {
                            if note.color == color { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
                        }
                    }.buttonStyle(.plain).help(color.name).accessibilityLabel(color.name)
                }
            }
            Divider()
            Picker("Font", selection: Binding(get: { note.font }, set: { value in store.updateNote(noteID) { $0.font = value } })) { ForEach(NoteFont.allCases) { font in Text(font.displayName).tag(font) } }
            HStack { Text("Text size").font(.system(size: 12)); Spacer(); Text("\(Int(note.fontSize)) pt").font(.system(size: 12)).monospacedDigit() }
            Slider(value: Binding(get: { note.fontSize }, set: { value in store.updateNote(noteID) { $0.fontSize = value } }), in: 12...36, step: 1)
        }
    }
    private func contentBinding<T>(_ keyPath: WritableKeyPath<NoteContent, T>, fallback: T) -> Binding<T> {
        Binding(get: { note?.content[keyPath: keyPath] ?? fallback }, set: { value in store.updateNote(noteID) { $0.content[keyPath: keyPath] = value } })
    }
    private func unlock() {
        busy = true
        Task { do { try await store.unlockNote(noteID, password: password); password = "" } catch { self.error = error.localizedDescription }; busy = false }
    }
    private func biometricUnlock() {
        busy = true
        Task {
            do {
                let secret = try await Task.detached { try BiometricNoteKeys.retrieve(noteID: noteID) }.value
                try await store.unlockNote(noteID, password: secret)
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct PasswordSheet: View {
    @Bindable var store: NoteStore
    let noteID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var biometrics = false
    @State private var busy = false
    @State private var error: String?
    private var protected: Bool { store.notes.first { $0.id == noteID }?.isPasswordProtected ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "lock.shield").font(.system(size: 27, weight: .light)); Spacer(); IconButton(symbol: "xmark", help: "Close password settings") { dismiss() } }
            Text(protected ? "Password settings" : "A little peace of mind.").font(.system(size: 25, weight: .semibold, design: .rounded))
            Text(protected ? "Enter the current password to remove protection or enable biometric unlock on this device." : "Your note and its history are encrypted. Keep your password somewhere safe; it cannot be recovered.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            SecureField(protected ? "Current password" : "Password (at least 8 characters)", text: $password).textFieldStyle(.roundedBorder)
            if !protected { SecureField("Confirm password", text: $confirm).textFieldStyle(.roundedBorder) }
            Toggle("Allow Face ID / Touch ID on this device", isOn: $biometrics).font(.system(size: 12))
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                if protected { Button("Remove password", role: .destructive) { run(remove: true) }.disabled(password.isEmpty || busy) }
                Spacer()
                Button(protected ? "Save" : "Protect note") { run(remove: false) }.buttonStyle(PillButtonStyle(filled: true)).disabled(busy || password.isEmpty || (!protected && (password.count < 8 || password != confirm)))
            }
            if busy { ProgressView().controlSize(.small) }
        }.padding(30).frame(idealWidth: 440).fixedSize(horizontal: false, vertical: true)
            .onAppear { biometrics = BiometricNoteKeys.hasCredential(noteID: noteID) }
    }
    private func run(remove: Bool) {
        busy = true
        Task {
            do {
                if remove { try await store.removePassword(noteID, password: password); BiometricNoteKeys.remove(noteID: noteID) }
                else {
                    if protected { try await store.unlockNote(noteID, password: password) } else { try await store.lockNote(noteID, password: password) }
                    if biometrics { try BiometricNoteKeys.save(password: password, noteID: noteID) }
                    else { BiometricNoteKeys.remove(noteID: noteID) }
                }
                password = ""; confirm = ""; dismiss()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct HistoryView: View {
    @Bindable var store: NoteStore
    let noteID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: UUID?
    private var note: StickyNote? { store.notes.first { $0.id == noteID } }
    var body: some View {
        let compact = sizeClass == .compact
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return VStack(alignment: .leading, spacing: 20) {
            HStack { VStack(alignment: .leading, spacing: 6) { Text("A little time travel.").font(.system(size: 26, weight: .semibold, design: .rounded)); Text("Revisit an earlier version of your note.").font(.system(size: 12)).foregroundStyle(Palette.secondary) }; Spacer(); IconButton(symbol: "xmark", help: "Close history") { dismiss() } }
            if let note, !note.history.isEmpty {
                layout {
                    ScrollView {
                        VStack(spacing: 7) {
                            ForEach(note.history.reversed()) { snapshot in
                                Button { selected = snapshot.id } label: { VStack(alignment: .leading, spacing: 5) { Text(snapshot.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(size: 12, weight: .medium)); Text(snapshot.content.title.isEmpty ? "Untitled note" : snapshot.content.title).font(.system(size: 11)).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(selected == snapshot.id ? Palette.accent.opacity(0.5) : Palette.sidebar, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                            }
                        }
                    }.frame(width: compact ? nil : 180).frame(maxHeight: compact ? 150 : nil)
                    if let snapshot = note.history.first(where: { $0.id == selected }) ?? note.history.last {
                        VStack(alignment: .leading, spacing: 15) {
                            ScrollView { Text(snapshot.content.plainText).frame(maxWidth: .infinity, alignment: .leading).padding(18).textSelection(.enabled) }.background(Color(hex: note.color.hex).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            Button("Restore this version") { store.restoreSnapshot(noteID: noteID, snapshotID: snapshot.id); dismiss() }.buttonStyle(PillButtonStyle(filled: true))
                        }
                    }
                }
            } else { EmptyState(symbol: "clock.arrow.circlepath", title: "Your story starts here.", message: "Earlier versions appear as you edit. Restoring a version also preserves your current note.") }
        }.padding(26).frame(idealWidth: 650, minHeight: 420, idealHeight: 520)
    }
}

struct PlainTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
