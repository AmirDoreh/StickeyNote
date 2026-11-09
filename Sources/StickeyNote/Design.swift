import SwiftUI
import StickeyCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark
    case automatic = "auto"

    static let storageKey = "stickeynote.appearance"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .automatic: "Auto"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .automatic: nil
        }
    }
}

/// Apply the same device preference to every window and presented settings view.
struct AppThemeModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .automatic

    func body(content: Content) -> some View {
        #if os(macOS)
        // AppKit also owns desktop panels and menus. Clearing the override lets
        // their effective appearance follow subsequent system changes in Auto.
        content.onChange(of: theme, initial: true) { _, theme in
            switch theme {
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            case .automatic: NSApp.appearance = nil
            }
        }
        #else
        content.preferredColorScheme(theme.colorScheme)
        #endif
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }

    init(light: String, dark: String) {
        #if os(macOS)
        let lightColor = NSColor(Color(hex: light))
        let darkColor = NSColor(Color(hex: dark))
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        })
        #else
        let lightColor = UIColor(Color(hex: light))
        let darkColor = UIColor(Color(hex: dark))
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
        #endif
    }
}

enum Palette {
    static let ink = Color(light: "292B24", dark: "EEF0E8")
    static let secondary = Color(light: "7D8175", dark: "B0B6A8")
    static let paper = Color(light: "FAFAF7", dark: "1C1F1A")
    static let sidebar = Color(light: "F0F1EB", dark: "23271F")
    static let surface = Color(light: "FFFFFF", dark: "2C3028")
    static let selection = Color(light: "E3E6D9", dark: "3E4930")
    static let filter = Color(light: "EDEEE7", dark: "353C2D")
    static let line = Color(light: "E5E7DE", dark: "3C4335")
    static let accent = Color(hex: "D9E982")
    static let accentInk = Color(hex: "292B24")
    static let noteInk = Color(hex: "292B24")
}

struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23).fill(Color(hex: "E0EC98"))
            Image(systemName: "note.text").font(.system(size: size * 0.53, weight: .medium)).foregroundStyle(Palette.accentInk)
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
            .foregroundStyle(filled ? Palette.accentInk : Palette.ink)
            .background(filled ? Palette.accent : Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
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
