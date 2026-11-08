import SwiftUI
import StickeyCore

struct ChecklistEditor: View {
    @Binding var items: [ChecklistItem]
    var fontSize: Double = 18
    var font: NoteFont = .system
    @FocusState private var focusedItem: UUID?

    private var completedCount: Int { items.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("\(completedCount) of \(items.count) completed")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if completedCount > 0 {
                    Menu {
                        Button("Uncheck all") { for index in items.indices { items[index].isCompleted = false } }
                        Button("Remove completed", role: .destructive) { items.removeAll(where: \.isCompleted) }
                    } label: { Image(systemName: "ellipsis").frame(width: 24, height: 20) }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Checklist options")
                }
            }
            .foregroundStyle(Color.black.opacity(0.48))

            if !items.isEmpty {
                GeometryReader { geometry in
                    Capsule().fill(Color.black.opacity(0.07))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.43))
                                .frame(width: geometry.size.width * Double(completedCount) / Double(items.count))
                        }
                }
                .frame(height: 3)
                .accessibilityLabel("Checklist progress")
                .accessibilityValue("\(completedCount) of \(items.count)")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        checklistRow(item)
                            .draggable(item.id.uuidString)
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first, let id = UUID(uuidString: value),
                                      let from = items.firstIndex(where: { $0.id == id }),
                                      let to = items.firstIndex(where: { $0.id == item.id }), from != to else { return false }
                                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                                return true
                            }
                    }
                }
            }
            .frame(minHeight: 100, maxHeight: .infinity)

            Button { addItem(after: items.last?.id) } label: {
                Label("Add an item", systemImage: "plus")
                    .font(.system(size: fontSize - 3))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.black.opacity(0.83))
        .background { shortcutButtons }
    }

    private func checklistRow(_ item: ChecklistItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                items[index].isCompleted.toggle()
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: fontSize + 2, weight: .light))
                    .foregroundStyle(Color.black.opacity(item.isCompleted ? 0.7 : 0.4))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")
            .accessibilityValue(item.text)

            TextField("New item", text: textBinding(for: item.id), axis: .vertical)
                .font(checklistFont)
                .textFieldStyle(.plain)
                .strikethrough(item.isCompleted)
                .foregroundStyle(Color.black.opacity(item.isCompleted ? 0.37 : 0.83))
                .focused($focusedItem, equals: item.id)
                .onSubmit { addItem(after: item.id) }
                .onKeyPress(keys: [.return], phases: .down) { event in
                    guard !event.modifiers.contains(.shift), !event.modifiers.contains(.command) else { return .ignored }
                    addItem(after: item.id)
                    return .handled
                }
                .accessibilityLabel("Checklist item")

            Menu {
                Button("Move up", systemImage: "arrow.up") { move(item.id, by: -1) }
                    .disabled(items.first?.id == item.id)
                Button("Move down", systemImage: "arrow.down") { move(item.id, by: 1) }
                    .disabled(items.last?.id == item.id)
                Divider()
                Button("Delete item", systemImage: "trash", role: .destructive) { items.removeAll { $0.id == item.id } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.black.opacity(0.3))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Item options")
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1).padding(.leading, fontSize + 14)
        }
    }

    private func textBinding(for id: UUID) -> Binding<String> {
        Binding(get: { items.first(where: { $0.id == id })?.text ?? "" }, set: { value in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].text = value
        })
    }

    private var checklistFont: Font {
        switch font {
        case .rounded: return .system(size: fontSize, design: .rounded)
        case .serif: return .system(size: fontSize, design: .serif)
        case .mono: return .system(size: fontSize, design: .monospaced)
        default: return font.familyName.map { .custom($0, size: fontSize) } ?? .system(size: fontSize)
        }
    }

    private func addItem(after id: UUID?) {
        let item = ChecklistItem(text: "")
        if let id, let index = items.firstIndex(where: { $0.id == id }) { items.insert(item, at: index + 1) }
        else { items.append(item) }
        focusedItem = item.id
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
        focusedItem = id
    }

    private var shortcutButtons: some View {
        HStack {
            Button("") { if let focusedItem { move(focusedItem, by: -1) } }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("") { if let focusedItem { move(focusedItem, by: 1) } }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button("") {
                if let index = items.firstIndex(where: { $0.id == focusedItem }) { items[index].isCompleted.toggle() }
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
        .hidden()
        .accessibilityHidden(true)
        .frame(width: 0, height: 0)
    }
}
