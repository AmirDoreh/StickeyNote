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
            let formatted = styles.isEmpty ? text : "<span style=\"\(styles.joined(separator: ";"))\">\(text)</span>"
            if let url = NoteLinks.safeURL(attributes[.link]) {
                let automatic = attributes[NoteLinks.automaticLink] != nil ? " data-auto-link=\"true\"" : ""
                html += "<a href=\"\(escape(url.absoluteString))\"\(automatic)>\(formatted)</a>"
            } else {
                html += formatted
            }
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
            guard ["a", "b", "strong", "i", "em", "u", "s", "strike", "del", "span", "p", "div", "li", "ul", "ol"].contains(tag) else { continue }
            if ["p", "div", "li"].contains(tag), result.length > 0, !result.string.hasSuffix("\n") { append("\n") }
            stack.append((tag, attributes))
            if tag == "a" {
                attributes.removeValue(forKey: .link)
                attributes.removeValue(forKey: NoteLinks.automaticLink)
                if let url = NoteLinks.safeURL(attribute("href", in: token)) {
                    attributes[.link] = url
                    if attribute("data-auto-link", in: token) == "true" { attributes[NoteLinks.automaticLink] = true }
                }
            }
            let style = attribute("style", in: token)?.lowercased() ?? ""
            let bold = ["b", "strong"].contains(tag) || style.range(of: "font-weight\\s*:\\s*(bold|[6-9]00)", options: .regularExpression) != nil
            let italic = ["i", "em"].contains(tag) || style.range(of: "font-style\\s*:\\s*italic", options: .regularExpression) != nil
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
            if tag == "u" || style.contains("underline") { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if ["s", "strike", "del"].contains(tag) || style.contains("line-through") { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
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

    private static func attribute(_ name: String, in token: String) -> String? {
        let pattern = "(?i)\\s" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) else { return nil }
        for index in 1...3 where match.range(at: index).location != NSNotFound {
            return unescape((token as NSString).substring(with: match.range(at: index)))
        }
        return nil
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

/// Link attributes are derived from the current text, so editing a URL cannot
/// leave an outdated destination attached to it. Display styling belongs to the
/// text view's linkTextAttributes and never replaces the user's own formatting.
enum NoteLinks {
    static let automaticLink = NSAttributedString.Key("StickeyAutomaticLink")
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func typingAttributes(from attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = attributes
        result.removeValue(forKey: .link)
        result.removeValue(forKey: automaticLink)
        return result
    }

    static func safeURL(_ value: Any?) -> URL? {
        let raw: String
        if let url = value as? URL { raw = url.absoluteString }
        else if let string = value as? String { raw = string }
        else { return nil }
        guard !raw.isEmpty, raw.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else { return nil }
        let normalized = raw.lowercased().hasPrefix("www.") ? "https://" + raw : raw
        guard let url = URL(string: normalized), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https": return url.host?.isEmpty == false ? url : nil
        case "mailto": return url.path.isEmpty ? nil : url
        default: return nil
        }
    }

    static func detectedLinks(in text: String) -> [(range: NSRange, url: URL)] {
        let source = text as NSString
        return (detector?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? []).compactMap { match in
            guard let detectedURL = match.url else { return nil }
            let displayed = source.substring(with: match.range)
            // Data detectors default schemeless websites to HTTP; prefer HTTPS.
            let candidate: Any = detectedURL.scheme?.lowercased() == "http" && !displayed.lowercased().hasPrefix("http://")
                ? "https://" + displayed : detectedURL
            guard let url = safeURL(candidate) else { return nil }
            return (match.range, url)
        }
    }

    static func refresh(in storage: NSMutableAttributedString) {
        guard storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let text = storage.string as NSString
        var explicitLinks: [(range: NSRange, url: URL)] = []
        storage.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard let url = safeURL(value) else { return }
            var automatic = false
            storage.enumerateAttribute(automaticLink, in: range) { marker, _, _ in
                if marker != nil { automatic = true }
            }
            // RTF does not preserve custom attributes. A URL used as its own
            // label is still an automatic link when that archive is reopened.
            if !automatic {
                let label = text.substring(with: range)
                automatic = detectedLinks(in: label).contains {
                    $0.range == NSRange(location: 0, length: (label as NSString).length) && $0.url == url
                }
            }
            if !automatic { explicitLinks.append((range, url)) }
        }
        let detected = detectedLinks(in: storage.string).filter { match in
            !explicitLinks.contains { NSIntersectionRange($0.range, match.range).length > 0 }
        }
        storage.beginEditing()
        storage.removeAttribute(.link, range: fullRange)
        storage.removeAttribute(automaticLink, range: fullRange)
        for link in explicitLinks { storage.addAttribute(.link, value: link.url, range: link.range) }
        for link in detected {
            storage.addAttributes([.link: link.url, automaticLink: true], range: link.range)
        }
        storage.endEditing()
    }
}
