#if os(macOS)
import SwiftUI
import AppKit
import StickeyCore

/// A real, compact desktop window editing the same note as the main app.
struct DesktopNoteView: View {
    @Bindable var store: NoteStore
    let noteID: UUID
    @ObservedObject private var desktop = FloatingNoteWindows.shared
    @State private var password = ""
    @State private var unlocking = false
    @State private var appleTask: Task<Void, Never>?
    @State private var appleOperation = UUID()
    @State private var appActive = NSApp.isActive
    @State private var error: String?
    @State private var showLock = false
    @State private var unlockAttempt = UUID()
    private var note: StickyNote? { store.notes.first { $0.id == noteID } }
    private var isBusy: Bool { unlocking || appleTask != nil }

    var body: some View {
        if let note {
            VStack(spacing: 0) {
                header(note)
                if store.isLocked(noteID) {
                    VStack(spacing: 12) {
                        Spacer(minLength: 4)
                        Image(systemName: "lock.shield").font(.system(size: 28, weight: .light))
                        Text("Note locked").font(.system(size: 15, weight: .semibold, design: .rounded))
                        if note.usesAppleAuthentication {
                            Text(AppleAuthenticationCopy.unlockDescription).font(.system(size: 11)).multilineTextAlignment(.center)
                        } else {
                            SecureField("Note PIN or password", text: $password).textFieldStyle(.roundedBorder).onSubmit(unlock)
                        }
                        Button(isBusy ? "Unlocking…" : "Unlock") {
                            if note.usesAppleAuthentication { runAppleOperation(protect: false) } else { unlock() }
                        }.buttonStyle(.bordered).disabled(isBusy || (!note.usesAppleAuthentication && password.isEmpty))
                        if !note.usesAppleAuthentication && BiometricNoteKeys.hasCredential(noteID: noteID) {
                            Button(BiometricAuthentication.label) { biometricUnlock() }.font(.system(size: 11)).buttonStyle(.plain).disabled(isBusy)
                        }
                        Spacer(minLength: 4)
                    }.padding(18).frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        TextField("Untitled note", text: content(\.title, fallback: ""), axis: .vertical)
                            .font(.system(size: 19, weight: .semibold, design: .rounded)).textFieldStyle(.plain).lineLimit(1...3).accessibilityLabel("Desktop note title")
                        if note.kind == .checklist {
                            compactChecklist(note)
                        } else {
                            RichNoteEditor(text: content(\.text, fallback: ""), richText: content(\.richText, fallback: nil), richHTML: content(\.richHTML, fallback: nil), font: note.font, fontSize: note.fontSize, minimumHeight: 60)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .overlay(alignment: .bottom) {
                                    if !note.content.strokes.isEmpty { DrawingPreview(strokes: note.content.strokes).frame(height: 65).allowsHitTesting(false) }
                                }
                        }
                    }.padding(.horizontal, 15).padding(.top, 7).padding(.bottom, 10)
                }
                footer(note)
            }
            .foregroundStyle(Palette.noteInk)
            .background(Color(hex: note.color.hex))
            .tint(Palette.noteInk)
            .environment(\.colorScheme, .light)
            .sheet(isPresented: $showLock) { NoteLockSettingsView(store: store, noteID: noteID) }
            .modifier(AppThemeModifier())
            .alert("Couldn’t complete that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .onChange(of: store.isLocked(noteID)) { _, locked in if locked { cancelUnlock() } }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                appActive = false
                if !AppleNoteSecurity.isPresentingSystemPrompt { cancelAppleOperation(); cancelUnlock(); showLock = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appActive = true }
            .onDisappear { cancelAppleOperation(); cancelUnlock() }
            .opacity(!appActive && AppleNoteSecurity.isAuthenticating ? 0 : 1)
            .accessibilityHidden(!appActive && AppleNoteSecurity.isAuthenticating)
            .overlay {
                if !appActive && AppleNoteSecurity.isAuthenticating {
                    Label("Note hidden", systemImage: "lock.shield").foregroundStyle(Palette.noteInk).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: note.color.hex))
                }
            }
        }
    }
    private func header(_ note: StickyNote) -> some View {
        HStack(spacing: 6) {
            Button { desktop.unpin(noteID) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).frame(width: 18, height: 22) }.buttonStyle(.plain).foregroundStyle(Palette.noteInk.opacity(0.45)).help("Remove from desktop; keep the note").accessibilityLabel("Remove from desktop")
            Text("ON YOUR DESKTOP").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(Palette.noteInk.opacity(0.4))
            Spacer()
            if !store.isLocked(noteID) {
                Button {
                    if note.isPasswordProtected { store.relockNote(noteID) } else { runAppleOperation(protect: true) }
                } label: { Image(systemName: "lock").font(.system(size: 11)).frame(width: 20, height: 20) }
                    .buttonStyle(.plain).help(note.isPasswordProtected ? "Lock note now" : "Lock with Apple authentication").accessibilityLabel("Lock note").disabled(isBusy)
            }
            Button { desktop.setAlwaysOnTop(!desktop.isAlwaysOnTop(noteID), for: noteID) } label: {
                Image(systemName: desktop.isAlwaysOnTop(noteID) ? "pin.fill" : "pin").font(.system(size: 11)).frame(width: 20, height: 20)
            }.buttonStyle(.plain).help(desktop.isAlwaysOnTop(noteID) ? "Stop keeping above other windows" : "Keep above other windows").accessibilityLabel("Keep above other windows")
            Menu {
                Button("Open in main app", systemImage: "arrow.up.right.square") { openMainNote() }
                Toggle("Keep above other windows", isOn: Binding(get: { desktop.isAlwaysOnTop(noteID) }, set: { desktop.setAlwaysOnTop($0, for: noteID) }))
                Menu("Note color") {
                    Picker("Note color", selection: Binding(
                        get: { note.color },
                        set: { color in store.updateNote(noteID) { $0.color = color } }
                    )) {
                        ForEach(NoteColor.allCases) { color in
                            Label {
                                Text(color.name)
                            } icon: {
                                Image(nsImage: NoteColorMenuSwatches.image(for: color))
                                    .renderingMode(.original)
                            }.labelStyle(.titleAndIcon).tag(color)
                        }
                    }.pickerStyle(.inline)
                }
                if !store.isLocked(noteID) {
                    Button(note.isPasswordProtected ? "Lock settings" : "Lock note", systemImage: "lock.shield") {
                        if note.isPasswordProtected { showLock = true } else { runAppleOperation(protect: true) }
                    }.disabled(isBusy)
                    if note.isPasswordProtected { Button("Lock note now", systemImage: "lock") { store.relockNote(noteID) } }
                }
                Divider()
                Button("Remove from desktop", systemImage: "xmark") { desktop.unpin(noteID) }
                Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) { store.deleteNote(noteID) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 13)).frame(width: 20, height: 20) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Desktop note actions")
        }.padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 3)
    }
    private func compactChecklist(_ note: StickyNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(note.content.items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Button { store.updateNote(noteID) { n in if let i = n.content.items.firstIndex(where: { $0.id == item.id }) { n.content.items[i].isCompleted.toggle() } } } label: {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square").font(.system(size: 15)).foregroundStyle(Palette.noteInk.opacity(item.isCompleted ? 0.45 : 0.8))
                        }.buttonStyle(.plain).accessibilityLabel("\(item.isCompleted ? "Uncheck" : "Complete") \(item.text)")
                        TextField("New item", text: Binding(get: { item.text }, set: { value in store.updateNote(noteID) { n in if let i = n.content.items.firstIndex(where: { $0.id == item.id }) { n.content.items[i].text = value } } }), axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 13)).strikethrough(item.isCompleted).opacity(item.isCompleted ? 0.5 : 1)
                    }
                }
                Button { store.updateNote(noteID) { $0.content.items.append(ChecklistItem()) } } label: { Label("Add item", systemImage: "plus").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(Palette.noteInk.opacity(0.5)).padding(.top, 4)
            }.padding(.top, 5)
        }.scrollIndicators(.hidden)
    }
    private func footer(_ note: StickyNote) -> some View {
        HStack {
            Text(store.isLocked(noteID) ? "Locked" : note.isPasswordProtected ? "Auto-lock: \(NoteLockDuration.label(store.autoLockSeconds))" : store.saveStatus).font(.system(size: 9)).lineLimit(1)
            Spacer()
            Button { openMainNote() } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 11)) }.buttonStyle(.plain).help("Open full editor").accessibilityLabel("Open full editor")
        }.foregroundStyle(Palette.noteInk.opacity(0.4)).padding(.horizontal, 14).padding(.bottom, 10)
    }
    private func openMainNote() { desktop.openMainNote?(noteID) }
    private func content<T>(_ path: WritableKeyPath<NoteContent,T>, fallback: T) -> Binding<T> {
        Binding(get: { note?.content[keyPath: path] ?? fallback }, set: { value in store.updateNote(noteID) { $0.content[keyPath: path] = value } })
    }
    private func unlock() {
        guard !password.isEmpty, !unlocking else { return }
        let secret = password
        let generation = store.securityGenerationToken(for: noteID)
        let attempt = UUID()
        unlockAttempt = attempt
        unlocking = true
        Task {
            do {
                guard unlockAttempt == attempt else { return }
                try await store.unlockNote(noteID, password: secret, expectedGeneration: generation)
                password = ""; error = nil
            } catch { if unlockAttempt == attempt { self.error = error.localizedDescription } }
            if unlockAttempt == attempt { unlocking = false }
        }
    }
    private func biometricUnlock() {
        guard !unlocking else { return }
        let id = noteID
        let generation = store.securityGenerationToken(for: id)
        let attempt = UUID()
        unlockAttempt = attempt
        unlocking = true
        Task {
            do {
                let secret = try await Task.detached { try BiometricNoteKeys.retrieve(noteID: id) }.value
                guard unlockAttempt == attempt, NSApp.isActive else { return }
                try await store.unlockNote(id, password: secret, expectedGeneration: generation)
                password = ""; error = nil
            } catch { if unlockAttempt == attempt { self.error = error.localizedDescription } }
            if unlockAttempt == attempt { unlocking = false }
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
        appleTask?.cancel(); appleTask = nil
    }
    private func cancelUnlock() {
        let wasUnlocking = unlocking
        unlockAttempt = UUID(); password = ""; error = nil; unlocking = false
        if wasUnlocking { store.relockNote(noteID) }
    }
}

/// Native macOS menus need a non-template image to preserve the actual shade.
@MainActor
private enum NoteColorMenuSwatches {
    private static let images: [String: NSImage] = Dictionary(uniqueKeysWithValues: NoteColor.allCases.map { color in
        let rgb = UInt64(color.hex, radix: 16) ?? 0
        let fill = NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                           green: Double((rgb >> 8) & 255) / 255,
                           blue: Double(rgb & 255) / 255, alpha: 1)
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { bounds in
            let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            fill.setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            return true
        }
        image.isTemplate = false
        return (color.rawValue, image)
    })

    static func image(for color: NoteColor) -> NSImage { images[color.rawValue]! }
}

struct DesktopMenu: View {
    @Bindable var store: NoteStore
    @ObservedObject private var desktop = FloatingNoteWindows.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("New desktop note", systemImage: "note.text.badge.plus") { newSticky(.text) }
        Button("New desktop checklist", systemImage: "checklist") { newSticky(.checklist) }
        Divider()
        if !desktop.pinnedIDs.isEmpty {
            ForEach(store.notes.filter { desktop.pinnedIDs.contains($0.id) && $0.deletedAt == nil }) { note in
                Button(store.isLocked(note.id) ? "Locked note" : note.displayTitle) { desktop.bringForward(note.id) }
            }
            Divider()
            Button("Show desktop notes") { desktop.showAll() }
            Button("Hide desktop notes") { desktop.hideAll() }
            Divider()
        }
        Button("Open all notes", systemImage: "square.grid.2x2") { openWindow(id: "main", value: MainWindowIdentity.library); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit Stickey Notes") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
    private func newSticky(_ kind: NoteKind) { let id = store.createNote(kind: kind); store.selectedNoteID = nil; desktop.configure(store: store); desktop.pin(id) }
}

@MainActor
final class StickeyAppDelegate: NSObject, NSApplicationDelegate {
    var store: NoteStore?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        Task {
            store.relockAll()
            await store.flush()
            if store.saveStatus == "Couldn’t save" {
                sender.reply(toApplicationShouldTerminate: false)
                let alert = NSAlert()
                alert.messageText = "Your latest changes haven’t been saved."
                alert.informativeText = "Stickey Notes will stay open so you can retry saving or export a backup from Settings."
                alert.addButton(withTitle: "Keep open")
                alert.runModal()
            } else { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
}
#endif
