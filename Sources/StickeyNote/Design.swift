import SwiftUI
import StickeyCore

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}

enum Palette {
    static let ink = Color(hex: "292B24")
    static let secondary = Color(hex: "7D8175")
    static let paper = Color(hex: "FAFAF7")
    static let sidebar = Color(hex: "F0F1EB")
    static let line = Color(hex: "E5E7DE")
    static let accent = Color(hex: "D9E982")
}

struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23).fill(Color(hex: "E0EC98"))
            Image(systemName: "note.text").font(.system(size: size * 0.53, weight: .medium)).foregroundStyle(Palette.ink)
        }.frame(width: size, height: size)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct PillButtonStyle: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(Palette.ink)
            .background(filled ? Palette.accent : Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.ink.opacity(filled ? 0 : 0.09)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func noteFont(_ font: NoteFont, size: Double) -> some View {
        let design: Font.Design = font == .serif ? .serif : font == .mono ? .monospaced : font == .rounded ? .rounded : .default
        return self.font(font.familyName.map { .custom($0, size: size) } ?? .system(size: size, design: design))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 35, weight: .light)).foregroundStyle(Palette.secondary).padding(22).background(Palette.sidebar, in: Circle())
            Text(title).font(.system(size: 23, weight: .semibold, design: .rounded))
            Text(message).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}
