import Foundation
#if os(macOS)
import AppKit
private typealias HTMLFont = NSFont
private typealias HTMLColor = NSColor
#else
import UIKit
private typealias HTMLFont = UIFont
private typealias HTMLColor = UIColor
#endif

/// A deliberately small, inert HTML bridge. It never loads images, stylesheets,
/// scripts or URLs from an imported archive.
enum RichHTMLBridge {
    static func encode(_ value: NSAttributedString) -> String {
        var html = ""
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            var styles: [String] = []
            if let font = attributes[.font] as? HTMLFont {
                #if os(macOS)
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.boldFontMask) { styles.append("font-weight:700") }
                if traits.contains(.italicFontMask) { styles.append("font-style:italic") }
                #else
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold) { styles.append("font-weight:700") }
                if traits.contains(.traitItalic) { styles.append("font-style:italic") }
                #endif
            }
            var decorations: [String] = []
            if (attributes[.underlineStyle] as? Int ?? 0) != 0 { decorations.append("underline") }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { decorations.append("line-through") }
            if !decorations.isEmpty { styles.append("text-decoration:\(decorations.joined(separator: " "))") }
            let text = escape((value.string as NSString).substring(with: range)).replacingOccurrences(of: "\n", with: "<br>")
            html += styles.isEmpty ? text : "<span style=\"\(styles.joined(separator: ";"))\">\(text)</span>"
        }
        return html
    }

    #if os(macOS)
    static func decode(_ html: String, matching text: String, font: NSFont) -> NSAttributedString? { decodeContent(html, matching: text, font: font) }
    #else
    static func decode(_ html: String, matching text: String, font: UIFont) -> NSAttributedString? { decodeContent(html, matching: text, font: font) }
    #endif

    private static func decodeContent(_ html: String, matching text: String, font: HTMLFont) -> NSAttributedString? {
        guard html.utf8.count <= 2_000_000 else { return nil }
        let clean = html.replacingOccurrences(of: "(?is)<(script|style|iframe|object)[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
        guard let tokenRegex = try? NSRegularExpression(pattern: "(?s)<[^>]*>|[^<]+") else { return nil }
        let source = clean as NSString
        let result = NSMutableAttributedString(string: "")
        var stack: [(String, [NSAttributedString.Key: Any])] = []
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: HTMLColor(white: 0.14, alpha: 1)]
        func append(_ value: String) { result.append(NSAttributedString(string: value, attributes: attributes)) }
        for match in tokenRegex.matches(in: clean, range: NSRange(location: 0, length: source.length)) {
            let token = source.substring(with: match.range)
            if !token.hasPrefix("<") { append(unescape(token)); continue }
            let lower = token.lowercased()
            let name = lower.replacingOccurrences(of: "^</?\\s*", with: "", options: .regularExpression)
                .prefix { $0.isLetter || $0.isNumber }
            let tag = String(name)
            if tag == "br" { append("\n"); continue }
            if lower.hasPrefix("</") {
                if let index = stack.lastIndex(where: { $0.0 == tag }) {
                    attributes = stack[index].1
                    stack.removeSubrange(index...)
                }
                if ["p", "div", "li"].contains(tag), !result.string.hasSuffix("\n") { append("\n") }
                continue
            }
            guard ["b", "strong", "i", "em", "u", "s", "strike", "del", "span", "p", "div", "li", "ul", "ol"].contains(tag) else { continue }
            if ["p", "div", "li"].contains(tag), result.length > 0, !result.string.hasSuffix("\n") { append("\n") }
            stack.append((tag, attributes))
            let bold = ["b", "strong"].contains(tag) || lower.range(of: "font-weight\\s*:\\s*(bold|[6-9]00)", options: .regularExpression) != nil
            let italic = ["i", "em"].contains(tag) || lower.range(of: "font-style\\s*:\\s*italic", options: .regularExpression) != nil
            let oldFont = attributes[.font] as? HTMLFont ?? font
            #if os(macOS)
            var traits = NSFontManager.shared.traits(of: oldFont)
            if bold { traits.insert(.boldFontMask) }
            if italic { traits.insert(.italicFontMask) }
            attributes[.font] = NSFontManager.shared.convert(oldFont, toHaveTrait: traits)
            #else
            var traits = oldFont.fontDescriptor.symbolicTraits
            if bold { traits.insert(.traitBold) }
            if italic { traits.insert(.traitItalic) }
            attributes[.font] = UIFont(descriptor: oldFont.fontDescriptor.withSymbolicTraits(traits) ?? oldFont.fontDescriptor, size: oldFont.pointSize)
            #endif
            if tag == "u" || lower.contains("underline") { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if ["s", "strike", "del"].contains(tag) || lower.contains("line-through") { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        }
        // Browsers frequently append one paragraph newline to contenteditable.
        while result.string.hasSuffix("\n") && result.length > (text as NSString).length { result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1)) }
        guard result.string == text else { return nil }
        return result
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func unescape(_ value: String) -> String {
        var result = value
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                let raw = (value as NSString).substring(with: match.range(at: 1))
                let number = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
                if let number, let scalar = UnicodeScalar(number), let range = Range(match.range, in: result) { result.replaceSubrange(range, with: String(scalar)) }
            }
        }
        return result.replacingOccurrences(of: "&nbsp;", with: "\u{00A0}").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }
}
