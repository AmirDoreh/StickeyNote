import SwiftUI
import UniformTypeIdentifiers
import StickeyCore

struct SettingsView: View {
    @Bindable var store: NoteStore
    @ObservedObject var sync: CloudKitSyncService
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var importing = false
    @State private var archive = Data()
    @State private var error: String?
    init(store: NoteStore, sync: CloudKitSyncService) { self.store = store; self.sync = sync }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { BrandMark(size: 42); VStack(alignment: .leading, spacing: 3) { Text("Make yourself at home.").font(.system(size: 23, weight: .semibold, design: .rounded)); Text("Stickey Notes · Settings").font(.system(size: 12)).foregroundStyle(Palette.secondary) }; Spacer(); IconButton(symbol: "xmark", help: "Close settings") { dismiss() } }.padding(26)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("YOUR NOTES, EVERYWHERE", symbol: "icloud") {
                        Text("Keep Mac, iPhone, iPad, and the web in sync with your private iCloud account.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        HStack {
                            Label(sync.status, systemImage: sync.isEnabled ? "checkmark.icloud" : "icloud.slash").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if sync.isSyncing { ProgressView().controlSize(.small) }
                        }.padding(.vertical, 6)
                        HStack {
                            Button(sync.isEnabled ? "Turn off iCloud" : "Connect iCloud") { if sync.isEnabled { sync.stop() } else { sync.start(store: store) } }.buttonStyle(PillButtonStyle(filled: !sync.isEnabled))
                            if sync.isEnabled { Button("Sync now") { Task { await sync.syncNow() } }.buttonStyle(PillButtonStyle()).disabled(sync.isSyncing) }
                        }
                        if let date = sync.lastSynced { Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                    }
                    section("BACKUP & RESTORE", symbol: "externaldrive") {
                        Text("Take your notes with you. Backups include groups, drawings, and history. Password-protected notes stay encrypted.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        HStack {
                            Button("Export backup") { do { archive = try store.exportArchive(); exporting = true } catch { self.error = error.localizedDescription } }.buttonStyle(PillButtonStyle())
                            Button("Import backup") { importing = true }.buttonStyle(PillButtonStyle())
                        }
                    }
                    section("A LITTLE PRIVACY", symbol: "lock.shield") {
                        Text("Notes stay on your device until you enable iCloud. Protected notes are encrypted with your password and hidden from widgets. Locking the app locks all protected notes.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        Button("Lock all protected notes") { store.relockAll() }.buttonStyle(PillButtonStyle())
                    }
                    section("YOUR DESKTOP, YOUR WAY", symbol: "rectangle.on.rectangle") {
                        Text("Add a Stickey Notes widget from your device’s widget gallery. On Mac, choose Keep on desktop in any note to create a small, editable sticky. Move or resize it, keep it above other windows, and close the main app window. Your desktop notes return after relaunch. Use the menu bar to create or show notes anytime.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
                        #if os(macOS)
                        HStack(spacing: 20) { Label("New note  ⌘N", systemImage: "note.text"); Label("Checklist  ⌘T", systemImage: "checklist") }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        #endif
                    }
                }.padding(.horizontal, 26).padding(.bottom, 26)
            }
        }.frame(idealWidth: 540, minHeight: 450, idealHeight: 650).background(Palette.paper).foregroundStyle(Palette.ink)
            .fileExporter(isPresented: $exporting, document: ArchiveDocument(data: archive), contentType: .json, defaultFilename: "Stickey Notes Backup.json") { result in if case let .failure(e) = result { error = e.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; try store.importArchive(Data(contentsOf: url)) } catch { self.error = error.localizedDescription }
            }
            .alert("Couldn’t complete that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) { Label(title, systemImage: symbol).font(.system(size: 10, weight: .semibold)).tracking(1.1); content() }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
    }
}

struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
