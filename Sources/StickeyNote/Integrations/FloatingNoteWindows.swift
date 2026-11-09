#if os(macOS)
import AppKit
import Combine
import CryptoKit
import Observation
import StickeyCore
import SwiftUI

/// Owns compact desktop windows independently of the library window. Each window
/// observes the same NoteStore; only window placement and pin preferences are copied.
@MainActor
final class FloatingNoteWindows: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = FloatingNoteWindows()

    @Published private(set) var pinnedIDs: Set<UUID> = []
    @Published private(set) var areNotesHidden = false
    var openMainNote: ((UUID) -> Void)?

    private var store: NoteStore?
    private var panels: [UUID: DesktopNotePanel] = [:]
    private var topmost: [UUID: Bool] = [:]
    private var savedFrames: [String: String] = [:]
    private var preferencePrefix = "StickeyNote.desktop"
    private var suppressedClosures: Set<UUID> = []
    private var observationGeneration = UUID()
    private var observing = false
    private var terminating = false
    private var frameSaveTask: Task<Void, Never>?
    private var widgetSaveTask: Task<Void, Never>?
    private var widgetExcludedIDs: Set<UUID> = []
    private var notifications: [NSObjectProtocol] = []
    private var workspaceNotifications: [NSObjectProtocol] = []

    private override init() {
        super.init()
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                AppleNoteSecurity.cancelAll()
                self?.terminating = true
                self?.persistFrames()
                if let store = self?.store { WidgetSnapshotWriter.update(notes: store.notes) }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitWindowsToScreens() }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if !AppleNoteSecurity.isPresentingSystemPrompt { self?.lockProtectedNotes() }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { AppleNoteSecurity.cancelAll(); self?.lockProtectedNotes() }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceNotifications.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name,
                                                                                           object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { AppleNoteSecurity.cancelAll(); self?.lockProtectedNotes() }
            })
        }
    }

    deinit {
        for token in notifications { NotificationCenter.default.removeObserver(token) }
        for token in workspaceNotifications { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    func configure(store: NoteStore) {
        if self.store === store {
            reconcileNotes()
            return
        }
        persistFrames()
        for id in Array(panels.keys) { closePanel(id) }
        observationGeneration = UUID()
        widgetSaveTask?.cancel()
        observing = false
        self.store = store
        let workspace = SHA256.hash(data: Data(store.directory.standardizedFileURL.path.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        preferencePrefix = "StickeyNote.desktop.\(workspace)"
        let defaults = UserDefaults.standard
        pinnedIDs = Set((defaults.stringArray(forKey: key("pins")) ?? []).compactMap(UUID.init(uuidString:)))
        savedFrames = defaults.dictionary(forKey: key("frames")) as? [String: String] ?? [:]
        topmost = Dictionary(uniqueKeysWithValues: (defaults.dictionary(forKey: key("topmost")) ?? [:]).compactMap { id, value in
            guard let id = UUID(uuidString: id), let enabled = value as? Bool else { return nil }
            return (id, enabled)
        })
        areNotesHidden = false
        restore()
        refreshWidgets(force: true)
        observeStore()
    }

    func pin(_ id: UUID) {
        guard liveNote(id) != nil else { return }
        pinnedIDs.insert(id)
        persistPreferences()
        areNotesHidden = false
        showPanel(id, focus: true)
    }

    func unpin(_ id: UUID) {
        AppleNoteSecurity.cancel(noteID: id)
        store?.relockNote(id)
        pinnedIDs.remove(id)
        closePanel(id)
        persistPreferences()
        if pinnedIDs.isEmpty { areNotesHidden = false }
        if let store { Task { await store.flush() } }
    }

    func toggle(_ id: UUID) { isPinned(id) ? unpin(id) : pin(id) }
    func isPinned(_ id: UUID) -> Bool { pinnedIDs.contains(id) }

    /// Restores every saved desktop note without bringing back the library window.
    func restore() {
        guard store != nil else { return }
        reconcileNotes()
        for id in pinnedIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            showPanel(id, focus: false)
        }
        if areNotesHidden { for panel in panels.values { panel.orderOut(nil) } }
    }

    func showAll() {
        areNotesHidden = false
        restore()
        for panel in panels.values { panel.orderFrontRegardless() }
    }

    func hideAll() {
        AppleNoteSecurity.cancelAll()
        persistFrames()
        areNotesHidden = !pinnedIDs.isEmpty
        for (id, panel) in panels {
            store?.relockNote(id)
            panel.orderOut(nil)
        }
        if let store { Task { await store.flush() } }
    }

    func bringForward(_ id: UUID) {
        guard isPinned(id), liveNote(id) != nil else { return }
        areNotesHidden = false
        showPanel(id, focus: true)
    }

    func setAlwaysOnTop(_ enabled: Bool, for id: UUID) {
        guard isPinned(id) else { return }
        topmost[id] = enabled
        panels[id]?.level = enabled ? .floating : .normal
        // Topmost changes also update controls in any other observed window.
        objectWillChange.send()
        persistPreferences()
    }

    func isAlwaysOnTop(_ id: UUID) -> Bool { topmost[id] ?? true }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? DesktopNotePanel,
              let id = panels.first(where: { $0.value === panel })?.key else { return }
        saveFrame(panel, id: id)
        panels.removeValue(forKey: id)
        guard !terminating, !suppressedClosures.contains(id) else { return }
        AppleNoteSecurity.cancel(noteID: id)
        pinnedIDs.remove(id)
        persistPreferences()
        store?.relockNote(id)
        if pinnedIDs.isEmpty { areNotesHidden = false }
        if let store { Task { await store.flush() } }
    }

    func windowDidMove(_ notification: Notification) { scheduleFrameSave() }
    func windowDidResize(_ notification: Notification) { scheduleFrameSave() }

    private func lockProtectedNotes() {
        guard let store else { return }
        // Panels outlive the library. Lock when the app backgrounds or the display
        // sleeps, while allowing its own settings sheets and biometric UI to take focus.
        store.relockAll()
        Task { await store.flush() }
    }

    private func showPanel(_ id: UUID, focus: Bool) {
        guard let store, let note = liveNote(id) else { return }
        let panel: DesktopNotePanel
        if let existing = panels[id] { panel = existing }
        else {
            panel = DesktopNotePanel(contentRect: NSRect(x: 0, y: 0, width: 290, height: 300),
                                     styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                     backing: .buffered, defer: false)
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isMovableByWindowBackground = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.hasShadow = true
            panel.minSize = NSSize(width: 220, height: 180)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
            let hostingView = DesktopNoteHostingView(rootView: DesktopNoteView(store: store, noteID: id))
            // The card draws its own header, so the hidden title bar needs no inset.
            hostingView.safeAreaRegions = []
            panel.contentView = hostingView
            panel.delegate = self
            panels[id] = panel
            if let saved = savedFrames[id.uuidString], validFrame(NSRectFromString(saved)) {
                panel.setFrame(fittedFrame(NSRectFromString(saved)), display: false)
            } else {
                panel.setFrame(initialFrame(size: panel.frame.size), display: false)
            }
        }
        updateAppearance(panel, note: note)
        panel.level = isAlwaysOnTop(id) ? .floating : .normal
        if focus {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else if !areNotesHidden { panel.orderFrontRegardless() }
    }

    private func closePanel(_ id: UUID) {
        guard let panel = panels[id] else { return }
        saveFrame(panel, id: id)
        suppressedClosures.insert(id)
        panel.close()
        panels.removeValue(forKey: id)
        suppressedClosures.remove(id)
    }

    private func liveNote(_ id: UUID) -> StickyNote? {
        store?.notes.first { $0.id == id && $0.deletedAt == nil }
    }

    private func reconcileNotes() {
        guard let store else { return }
        let notes = Dictionary(uniqueKeysWithValues: store.notes.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
        for id in pinnedIDs where notes[id] == nil { unpin(id) }
        for (id, panel) in panels {
            if let note = notes[id] { updateAppearance(panel, note: note) }
        }
    }

    private func updateAppearance(_ panel: DesktopNotePanel, note: StickyNote) {
        panel.title = store?.isLocked(note.id) == true ? "Locked note" : note.displayTitle
        let value = UInt64(note.color.hex, radix: 16) ?? 0xF7E999
        panel.backgroundColor = NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                                        green: Double((value >> 8) & 255) / 255,
                                        blue: Double(value & 255) / 255, alpha: 1)
    }

    private func observeStore() {
        guard !observing, let store else { return }
        observing = true
        let generation = observationGeneration
        withObservationTracking { _ = store.notes } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observationGeneration == generation else { return }
                self.observing = false
                self.reconcileNotes()
                self.refreshWidgets()
                self.observeStore()
            }
        }
    }

    private func refreshWidgets(force: Bool = false) {
        guard let store else { return }
        let excluded = Set(store.notes.filter { $0.isPasswordProtected || $0.deletedAt != nil }.map(\.id))
        let protectionChanged = excluded != widgetExcludedIDs
        widgetExcludedIDs = excluded
        widgetSaveTask?.cancel()
        if force || protectionChanged {
            // Never leave a newly protected or deleted note in shared previews.
            WidgetSnapshotWriter.update(notes: store.notes)
        } else {
            let generation = observationGeneration
            widgetSaveTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                guard let self, self.observationGeneration == generation, let store = self.store else { return }
                WidgetSnapshotWriter.update(notes: store.notes)
            }
        }
    }

    private func key(_ suffix: String) -> String { "\(preferencePrefix).\(suffix)" }

    private func persistPreferences() {
        let defaults = UserDefaults.standard
        defaults.set(pinnedIDs.map(\.uuidString).sorted(), forKey: key("pins"))
        defaults.set(Dictionary(uniqueKeysWithValues: topmost.map { ($0.key.uuidString, $0.value) }), forKey: key("topmost"))
    }

    private func scheduleFrameSave() {
        frameSaveTask?.cancel()
        frameSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            self?.persistFrames()
        }
    }

    private func saveFrame(_ panel: NSPanel, id: UUID) {
        guard validFrame(panel.frame) else { return }
        savedFrames[id.uuidString] = NSStringFromRect(panel.frame)
        UserDefaults.standard.set(savedFrames, forKey: key("frames"))
    }

    private func persistFrames() {
        frameSaveTask?.cancel()
        for (id, panel) in panels where validFrame(panel.frame) {
            savedFrames[id.uuidString] = NSStringFromRect(panel.frame)
        }
        UserDefaults.standard.set(savedFrames, forKey: key("frames"))
    }

    private func validFrame(_ frame: NSRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width >= 220 && frame.height >= 180
    }

    private func initialFrame(size: NSSize) -> NSRect {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return NSRect(origin: NSPoint(x: 100, y: 100), size: size) }
        let offset = CGFloat(max(0, panels.count - 1) % 8) * 22
        return fittedFrame(NSRect(x: visible.maxX - size.width - 30 - offset,
                                  y: visible.maxY - size.height - 34 - offset, width: size.width, height: size.height))
    }

    private func fittedFrame(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.max { first, second in
            let a = first.visibleFrame.intersection(frame), b = second.visibleFrame.intersection(frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        let size = NSSize(width: min(max(220, frame.width), visible.width),
                          height: min(max(180, frame.height), visible.height))
        let x = min(max(frame.minX, visible.minX), visible.maxX - size.width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - size.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func fitWindowsToScreens() {
        for panel in panels.values { panel.setFrame(fittedFrame(panel.frame), display: true) }
        persistFrames()
    }
}

private final class DesktopNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DesktopNoteHostingView: NSHostingView<DesktopNoteView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
}
#endif
