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
    @State private var appleTask: Task<Void, Never>?
    @State private var appleOperation = UUID()
    @State private var unlockAttempt = UUID()
    @State private var authenticationScenePhase: ScenePhase = .active
    @State private var export = false
    private var note: StickyNote? { store.notes.first { $0.id == noteID } }
    private var usesAppleAuthentication: Bool { note?.usesAppleAuthentication == true }
    private var isBusy: Bool { busy || appleTask != nil }
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
                        }
                        .foregroundStyle(Palette.noteInk)
                        .tint(Palette.noteInk)
                        .background(Color(hex: note.color.hex).opacity(0.8))
                        .background(Color(hex: "FAFAF7"))
                        .environment(\.colorScheme, .light)
                    }
                    bottomBar(note)
                }.background(Palette.paper).foregroundStyle(Palette.ink)
                    .sheet(isPresented: $showQR) { ProtectedNoteQRCodeView(store: store, noteID: noteID) }
                    .sheet(isPresented: $showHistory) { HistoryView(store: store, noteID: noteID) }
                    .sheet(isPresented: $showLock) { NoteLockSettingsView(store: store, noteID: noteID) }
                    .popover(isPresented: $showAppearance) { appearance(note).padding(22).frame(width: 295) }
                    .fileExporter(isPresented: $export, document: PlainTextDocument(text: note.content.plainText), contentType: .plainText, defaultFilename: note.displayTitle + ".txt") { result in if case let .failure(e) = result { error = e.localizedDescription } }
            } else { EmptyState(symbol: "note.text", title: "Note unavailable", message: "This note may have been removed on another device.") }
        }
        #if os(macOS)
        .frame(minWidth: 590, idealWidth: 700, minHeight: 590, idealHeight: 700)
        #endif
        .alert("Couldn’t complete that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            authenticationScenePhase = phase
            #if os(iOS)
            if phase == .background { cancelAppleOperation(); clearPrivatePresentation(); showLock = false }
            #else
            if phase != .active && !AppleNoteSecurity.isPresentingSystemPrompt { cancelAppleOperation(); clearPrivatePresentation(); showLock = false }
            #endif
        }
        .onChange(of: store.isLocked(noteID)) { _, locked in if locked { clearPrivatePresentation() } }
        .onAppear { authenticationScenePhase = scenePhase }
        .onDisappear { cancelAppleOperation(); clearPrivatePresentation() }
        .modifier(InactiveNotePrivacy())
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
                IconButton(symbol: "lock", help: note.isPasswordProtected ? "Lock note now" : "Lock with Apple authentication") {
                    if note.isPasswordProtected { store.relockNote(noteID) } else { runAppleOperation(protect: true) }
                }.disabled(isBusy)
                Menu {
                    Button("Show QR code", systemImage: "qrcode") { showQR = true }
                    ShareLink(item: note.content.plainText) { Label("Share note", systemImage: "square.and.arrow.up") }
                    Button("Export as text", systemImage: "doc.text") { export = true }
                    #if os(macOS)
                    Button("Keep on desktop", systemImage: "macwindow.on.rectangle") { FloatingNoteWindows.shared.pin(noteID) }
                    #endif
                    Button("Version history", systemImage: "clock.arrow.circlepath") { showHistory = true }
                    Button(note.isPasswordProtected ? "Lock settings" : "Lock note", systemImage: "lock") {
                        if note.isPasswordProtected { showLock = true } else { runAppleOperation(protect: true) }
                    }.disabled(isBusy)
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
                Text("\(note.content.items.filter(\.isCompleted).count) of \(note.content.items.count) completed").font(.system(size: 12)).foregroundStyle(Palette.noteInk.opacity(0.5))
            }
        }.padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 20)
    }
    private var lockedContent: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Palette.secondary)
            Text("Note locked").font(.system(size: 28, weight: .medium, design: .serif))
            Text(usesAppleAuthentication ? AppleAuthenticationCopy.unlockDescription : "Enter this note’s existing PIN or password.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            if !usesAppleAuthentication {
                SecureField("Note PIN or password", text: $password).textFieldStyle(.roundedBorder).frame(maxWidth: 280).onSubmit(unlock)
            }
            Button {
                if usesAppleAuthentication { runAppleOperation(protect: false) } else { unlock() }
            } label: {
                if isBusy { ProgressView().controlSize(.small) } else { Text("Unlock note") }
            }.buttonStyle(PillButtonStyle(filled: true)).disabled(isBusy || (!usesAppleAuthentication && password.isEmpty))
            if !usesAppleAuthentication && BiometricNoteKeys.hasCredential(noteID: noteID) {
                Button(BiometricAuthentication.label) { biometricUnlock() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary).disabled(isBusy)
            }
            Text("Locks again after \(NoteLockDuration.label(store.autoLockSeconds)).").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            Spacer()
        }.frame(maxWidth: .infinity).padding(30)
    }
    private func bottomBar(_ note: StickyNote) -> some View {
        HStack(spacing: 6) {
            Image(systemName: note.isPasswordProtected ? "lock.shield" : "checkmark.circle").font(.system(size: 11))
            Text(store.isLocked(noteID) ? "Locked" : note.isPasswordProtected ? "Auto-lock: \(NoteLockDuration.label(store.autoLockSeconds))" : store.saveStatus).font(.system(size: 11))
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
                            if note.color == color { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.noteInk) }
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
        guard !password.isEmpty, !busy else { return }
        let secret = password
        let generation = store.securityGenerationToken(for: noteID)
        let attempt = UUID()
        unlockAttempt = attempt
        busy = true
        Task {
            do {
                guard unlockAttempt == attempt else { return }
                try await store.unlockNote(noteID, password: secret, expectedGeneration: generation); password = ""
            }
            catch { if unlockAttempt == attempt { self.error = error.localizedDescription } }
            if unlockAttempt == attempt { busy = false }
        }
    }
    private func biometricUnlock() {
        guard !busy else { return }
        let id = noteID
        let generation = store.securityGenerationToken(for: id)
        let attempt = UUID()
        unlockAttempt = attempt
        busy = true
        Task {
            do {
                let secret = try await Task.detached { try BiometricNoteKeys.retrieve(noteID: id) }.value
                #if os(iOS)
                // Face ID temporarily makes the scene inactive. Keep the
                // authenticated result private until the app is active again.
                while authenticationScenePhase == .inactive && unlockAttempt == attempt {
                    try await Task.sleep(for: .milliseconds(50))
                }
                #endif
                guard unlockAttempt == attempt, authenticationScenePhase == .active else { return }
                try await store.unlockNote(id, password: secret, expectedGeneration: generation)
            } catch { if unlockAttempt == attempt { self.error = error.localizedDescription } }
            if unlockAttempt == attempt { busy = false }
        }
    }
    private func runAppleOperation(protect: Bool) {
        guard !isBusy else { return }
        let operation = UUID()
        appleOperation = operation
        error = nil
        appleTask = Task {
            do {
                if protect { try await AppleNoteSecurity.protect(store: store, noteID: noteID) }
                else { try await AppleNoteSecurity.unlock(store: store, noteID: noteID) }
            } catch {
                if appleOperation == operation && !Task.isCancelled && !(error is CancellationError) { self.error = error.localizedDescription }
            }
            if appleOperation == operation { appleTask = nil }
        }
    }
    private func cancelAppleOperation() {
        appleOperation = UUID()
        appleTask?.cancel()
        appleTask = nil
    }
    private func clearPrivatePresentation() {
        let wasUnlocking = busy
        showQR = false; showHistory = false; showAppearance = false; export = false
        password = ""; error = nil; busy = false; unlockAttempt = UUID()
        if wasUnlocking { store.relockNote(noteID) }
    }
}

/// Observe the store inside the presented view so an auto-lock immediately
/// removes the QR image, including while the sheet is animating closed.
private struct ProtectedNoteQRCodeView: View {
    @Bindable var store: NoteStore
    let noteID: UUID
    var body: some View {
        Group {
            if !store.isLocked(noteID), let note = store.notes.first(where: { $0.id == noteID }) {
                QRCodeView(text: note.content.plainText)
            } else { Text("Note locked").padding(30) }
        }.modifier(InactiveNotePrivacy())
    }
}

struct NoteLockSettingsView: View {
    @Bindable var store: NoteStore
    let noteID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var password = ""
    @State private var task: Task<Void, Never>?
    @State private var operation = UUID()
    @State private var error: String?
    private var note: StickyNote? { store.notes.first { $0.id == noteID } }
    private var usesAppleAuthentication: Bool { note?.usesAppleAuthentication == true }
    private var isProtected: Bool { note?.isPasswordProtected == true }
    var body: some View {
        Group {
            #if os(macOS)
            form.fixedSize(horizontal: false, vertical: true)
            #else
            ScrollView { form }.scrollDismissesKeyboard(.interactively)
            #endif
        }.frame(idealWidth: 440)
            .onChange(of: scenePhase) { _, phase in
                #if os(iOS)
                if phase == .background { cancelOperation(); dismiss() }
                #else
                if phase != .active && !AppleNoteSecurity.isPresentingSystemPrompt { cancelOperation(); dismiss() }
                #endif
            }
            .onChange(of: store.isLocked(noteID)) { _, locked in if locked { password = "" } }
            .onDisappear { cancelOperation() }
            .modifier(InactiveNotePrivacy())
    }
    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "lock.shield").font(.system(size: 27, weight: .light)); Spacer(); IconButton(symbol: "xmark", help: "Close lock settings") { dismiss() } }
            Text("Lock settings").font(.system(size: 25, weight: .semibold, design: .rounded))
            if usesAppleAuthentication {
                Text(AppleAuthenticationCopy.unlockDescription).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Text("Apple verifies your identity in its system prompt. This note’s unlock key stays on this device.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            } else if isProtected {
                Text("This note uses an existing note PIN or password. You can switch it to Apple’s system authentication on this device.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                Button("Use Apple authentication") { run(remove: false) }.buttonStyle(PillButtonStyle(filled: true)).disabled(task != nil || store.isLocked(noteID))
                SecureField("Current note PIN or password", text: $password).textFieldStyle(.roundedBorder)
                Text("Only needed to remove the existing lock.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            NoteAutoLockPicker(store: store)
            Text("Applies to all protected notes on this device, from the time you unlock each note.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                if isProtected {
                    Button("Remove lock", role: .destructive) { run(remove: true) }.disabled(task != nil || (!usesAppleAuthentication && password.isEmpty))
                } else {
                    Button("Lock note") { run(remove: false) }.buttonStyle(PillButtonStyle(filled: true)).disabled(task != nil)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(PillButtonStyle()).disabled(task != nil)
            }
            if task != nil { ProgressView().controlSize(.small) }
        }.padding(30)
    }
    private func run(remove: Bool) {
        guard task == nil else { return }
        let credential = password
        let apple = usesAppleAuthentication
        let attempt = UUID()
        operation = attempt
        error = nil
        task = Task {
            do {
                try Task.checkCancellation()
                if remove {
                    if apple { try await AppleNoteSecurity.removeProtection(store: store, noteID: noteID) }
                    else {
                        try await store.removePassword(noteID, password: credential)
                        BiometricNoteKeys.remove(noteID: noteID)
                    }
                } else { try await AppleNoteSecurity.protect(store: store, noteID: noteID) }
                guard !Task.isCancelled, operation == attempt else { return }
                password = ""; task = nil; dismiss()
            } catch {
                if operation == attempt {
                    if !Task.isCancelled && !(error is CancellationError) { self.error = error.localizedDescription }
                    task = nil
                }
            }
        }
    }
    private func cancelOperation() {
        operation = UUID()
        if task != nil {
            task?.cancel()
            store.relockNote(noteID)
        }
        task = nil; password = ""
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
            if store.isLocked(noteID) {
                EmptyState(symbol: "lock.shield", title: "Note locked", message: "Unlock this note to view its history.")
            } else if let note, !note.history.isEmpty {
                layout {
                    ScrollView {
                        VStack(spacing: 7) {
                            ForEach(note.history.reversed()) { snapshot in
                                Button { selected = snapshot.id } label: { VStack(alignment: .leading, spacing: 5) { Text(snapshot.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(size: 12, weight: .medium)); Text(snapshot.content.title.isEmpty ? "Untitled note" : snapshot.content.title).font(.system(size: 11)).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(selected == snapshot.id ? Palette.selection : Palette.sidebar, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                            }
                        }
                    }.frame(width: compact ? nil : 180).frame(maxHeight: compact ? 150 : nil)
                    if let snapshot = note.history.first(where: { $0.id == selected }) ?? note.history.last {
                        VStack(alignment: .leading, spacing: 15) {
                            ScrollView { Text(snapshot.content.plainText).frame(maxWidth: .infinity, alignment: .leading).padding(18).textSelection(.enabled) }
                                .foregroundStyle(Palette.noteInk)
                                .background(Color(hex: note.color.hex).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                                .background(Color(hex: "FAFAF7"), in: RoundedRectangle(cornerRadius: 12))
                                .environment(\.colorScheme, .light)
                            Button("Restore this version") { store.restoreSnapshot(noteID: noteID, snapshotID: snapshot.id); dismiss() }.buttonStyle(PillButtonStyle(filled: true))
                        }
                    }
                }
            } else { EmptyState(symbol: "clock.arrow.circlepath", title: "Your story starts here.", message: "Earlier versions appear as you edit. Restoring a version also preserves your current note.") }
        }.padding(26).frame(idealWidth: 650, minHeight: 420, idealHeight: 520)
            .modifier(InactiveNotePrivacy())
    }
}

struct PlainTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
