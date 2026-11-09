import SwiftUI
import StickeyCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum RichFormatAction { case bold, italic, underline, strike, bullet, numbered }

struct RichTextCommand: Equatable {
    let id = UUID()
    let action: RichFormatAction
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// A native text editor. RTF keeps formatting portable between iPhone and Mac.
struct RichNoteEditor: View {
    @Binding var text: String
    @Binding var richText: Data?
    @Binding var richHTML: String?
    var font: NoteFont
    var fontSize: Double
    var minimumHeight: CGFloat = 180
    var command: RichTextCommand? = nil

    init(text: Binding<String>, richText: Binding<Data?>, richHTML: Binding<String?> = .constant(nil), font: NoteFont, fontSize: Double, minimumHeight: CGFloat = 180, command: RichTextCommand? = nil) {
        _text = text; _richText = richText; _richHTML = richHTML
        self.font = font; self.fontSize = fontSize; self.minimumHeight = max(0, minimumHeight); self.command = command
    }

    var body: some View {
        NativeRichTextEditor(text: $text, richText: $richText, richHTML: $richHTML, font: font, fontSize: fontSize, minimumHeight: minimumHeight, command: command)
            .frame(minHeight: minimumHeight)
            .accessibilityLabel("Note text")
    }
}

/// An editing surface with a compact, keyboard-accessible formatting toolbar.
struct RichEditorPanel: View {
    @Binding var text: String
    @Binding var richText: Data?
    @Binding var richHTML: String?
    var font: NoteFont
    var fontSize: Double
    @State private var command: RichTextCommand?

    init(text: Binding<String>, richText: Binding<Data?>, richHTML: Binding<String?> = .constant(nil), font: NoteFont, fontSize: Double) {
        _text = text; _richText = richText; _richHTML = richHTML
        self.font = font; self.fontSize = fontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 3) {
                formatButton("Bold", symbol: "bold", action: .bold)
                formatButton("Italic", symbol: "italic", action: .italic)
                formatButton("Underline", symbol: "underline", action: .underline)
                formatButton("Strikethrough", symbol: "strikethrough", action: .strike)
                Divider().frame(height: 15).padding(.horizontal, 5)
                formatButton("Bulleted list", symbol: "list.bullet", action: .bullet)
                formatButton("Numbered list", symbol: "list.number", action: .numbered)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.black.opacity(0.58))
            RichNoteEditor(text: $text, richText: $richText, richHTML: $richHTML, font: font, fontSize: fontSize, command: command)
        }
    }

    @ViewBuilder private func formatButton(_ title: String, symbol: String, action: RichFormatAction) -> some View {
        let button = Button { command = RichTextCommand(action: action) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 28).contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        switch action {
        case .bold: button.keyboardShortcut("b", modifiers: .command)
        case .italic: button.keyboardShortcut("i", modifiers: .command)
        case .underline: button.keyboardShortcut("u", modifiers: .command)
        default: button
        }
    }
}

#if os(macOS)
private struct NativeRichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var richText: Data?
    @Binding var richHTML: String?
    var font: NoteFont
    var fontSize: Double
    var minimumHeight: CGFloat
    var command: RichTextCommand?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = NSTextView()
        view.delegate = context.coordinator
        view.isRichText = true
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.textColor = NSColor(calibratedWhite: 0.14, alpha: 1)
        view.insertionPointColor = NSColor(calibratedWhite: 0.14, alpha: 1)
        view.isAutomaticSpellingCorrectionEnabled = true
        // Refresh links ourselves so saved text and URLs without a trailing space
        // behave just like newly typed links.
        view.isAutomaticLinkDetectionEnabled = false
        view.linkTextAttributes = [.foregroundColor: NSColor.systemBlue,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .cursor: NSCursor.pointingHand]
        view.displaysLinkToolTips = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainerInset = NSSize(width: 0, height: 5)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.minSize = NSSize(width: 0, height: minimumHeight)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel("Note text")
        scroll.documentView = view
        context.coordinator.editor = view
        context.coordinator.replaceContent()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let view = coordinator.editor else { return }
        view.minSize = NSSize(width: 0, height: minimumHeight)
        if view.string != text || richText != coordinator.lastData || richHTML != coordinator.lastHTML {
            coordinator.replaceContent()
        }
        if coordinator.lastFontName != font.rawValue || coordinator.lastFontSize != fontSize {
            coordinator.lastFontName = font.rawValue
            coordinator.lastFontSize = fontSize
            DispatchQueue.main.async { [weak coordinator] in coordinator?.applyBaseFont() }
        }
        if let command, command.id != coordinator.lastCommand {
            coordinator.lastCommand = command.id
            DispatchQueue.main.async { [weak coordinator] in coordinator?.apply(command.action) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeRichTextEditor
        weak var editor: NSTextView?
        var lastData: Data?
        var lastHTML: String?
        var lastCommand: UUID?
        var lastFontName: String?
        var lastFontSize: Double = 0
        var isUpdating = false

        init(_ parent: NativeRichTextEditor) { self.parent = parent }

        var baseFont: NSFont {
            let system = NSFont.systemFont(ofSize: parent.fontSize)
            switch parent.font {
            case .rounded: return NSFont(descriptor: system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor, size: parent.fontSize) ?? system
            case .serif: return NSFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: parent.fontSize) ?? system
            case .mono: return NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            default: return parent.font.familyName.flatMap { NSFont(name: $0, size: parent.fontSize) } ?? system
            }
        }

        func replaceContent() {
            guard let view = editor else { return }
            isUpdating = true
            let range = view.selectedRange()
            if let data = parent.richText,
               let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
               value.string == parent.text {
                view.textStorage?.setAttributedString(value)
            } else if let html = parent.richHTML, let value = RichHTMLBridge.decode(html, matching: parent.text, font: baseFont) {
                view.textStorage?.setAttributedString(value)
            } else {
                view.textStorage?.setAttributedString(NSAttributedString(string: parent.text, attributes: [.font: baseFont, .foregroundColor: NSColor(calibratedWhite: 0.14, alpha: 1)]))
            }
            if let storage = view.textStorage { NoteLinks.refresh(in: storage) }
            let count = (view.string as NSString).length
            view.setSelectedRange(NSRange(location: min(range.location, count), length: min(range.length, max(0, count - min(range.location, count)))))
            view.typingAttributes[.font] = baseFont
            view.typingAttributes = NoteLinks.typingAttributes(from: view.typingAttributes)
            lastData = parent.richText
            lastHTML = parent.richHTML
            lastFontName = parent.font.rawValue
            lastFontSize = parent.fontSize
            isUpdating = false
        }

        func applyBaseFont() {
            guard let view = editor, let storage = view.textStorage else { return }
            isUpdating = true
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                let traits = ((value as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []).intersection([.boldFontMask, .italicFontMask])
                storage.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: traits), range: range)
            }
            storage.endEditing()
            view.typingAttributes[.font] = baseFont
            lastFontName = parent.font.rawValue
            lastFontSize = parent.fontSize
            isUpdating = false
            publish()
        }

        func textDidChange(_ notification: Notification) { if !isUpdating { publish() } }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = NoteLinks.safeURL(link) { NSWorkspace.shared.open(url) }
            return true
        }

        func publish() {
            guard !isUpdating, let view = editor, let storage = view.textStorage else { return }
            isUpdating = true
            defer { isUpdating = false }
            if !view.hasMarkedText() {
                NoteLinks.refresh(in: storage)
                view.typingAttributes = NoteLinks.typingAttributes(from: view.typingAttributes)
            }
            let data = try? storage.data(from: NSRange(location: 0, length: storage.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            let html = RichHTMLBridge.encode(storage)
            lastData = data
            lastHTML = html
            if parent.text != view.string { parent.text = view.string }
            if parent.richText != data { parent.richText = data }
            if parent.richHTML != html { parent.richHTML = html }
        }

        func apply(_ action: RichFormatAction) {
            guard let view = editor, let storage = view.textStorage else { return }
            view.window?.makeFirstResponder(view)
            let range = view.selectedRange()
            if action == .bullet || action == .numbered {
                let paragraph = (view.string as NSString).paragraphRange(for: range)
                let original = (view.string as NSString).substring(with: paragraph)
                let lines = original.components(separatedBy: "\n")
                let replacement = lines.enumerated().map { index, line in
                    if line.isEmpty && index == lines.count - 1 && index > 0 { return line }
                    return (action == .bullet ? "• " : "\(index + 1). ") + line
                }.joined(separator: "\n")
                view.insertText(replacement, replacementRange: paragraph)
                publish()
                return
            }
            var attributes = range.length == 0 ? view.typingAttributes : storage.attributes(at: min(range.location, max(0, storage.length - 1)), effectiveRange: nil)
            if action == .bold || action == .italic {
                let trait: NSFontTraitMask = action == .bold ? .boldFontMask : .italicFontMask
                let current = attributes[.font] as? NSFont ?? baseFont
                let hasTrait = NSFontManager.shared.traits(of: current).contains(trait)
                attributes[.font] = hasTrait ? NSFontManager.shared.convert(current, toNotHaveTrait: trait) : NSFontManager.shared.convert(current, toHaveTrait: trait)
            } else {
                let key: NSAttributedString.Key = action == .underline ? .underlineStyle : .strikethroughStyle
                attributes[key] = (attributes[key] as? Int ?? 0) == 0 ? NSUnderlineStyle.single.rawValue : 0
            }
            if range.length == 0 { view.typingAttributes = attributes }
            else {
                let old = storage.attributedSubstring(from: range)
                view.undoManager?.registerUndo(withTarget: self) { target in
                    guard let editor = target.editor, let textStorage = editor.textStorage, NSMaxRange(range) <= textStorage.length else { return }
                    textStorage.replaceCharacters(in: range, with: old)
                    target.publish()
                }
                if action == .bold || action == .italic {
                    storage.addAttribute(.font, value: attributes[.font]!, range: range)
                } else {
                    let key: NSAttributedString.Key = action == .underline ? .underlineStyle : .strikethroughStyle
                    storage.addAttribute(key, value: attributes[key]!, range: range)
                }
                view.didChangeText()
            }
            publish()
        }
    }
}
#else
private struct NativeRichTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var richText: Data?
    @Binding var richHTML: String?
    var font: NoteFont
    var fontSize: Double
    var minimumHeight: CGFloat
    var command: RichTextCommand?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.isEditable = true
        view.isSelectable = true
        view.allowsEditingTextAttributes = true
        view.textContainerInset = UIEdgeInsets(top: 5, left: 0, bottom: 12, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.keyboardDismissMode = .interactive
        view.accessibilityLabel = "Note text"
        view.tintColor = .darkGray
        view.linkTextAttributes = [.foregroundColor: UIColor.systemBlue,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue]
        let linkTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.openLink(_:)))
        linkTap.delegate = context.coordinator
        view.addGestureRecognizer(linkTap)
        context.coordinator.editor = view
        context.coordinator.replaceContent()
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if view.text != text || richText != coordinator.lastData || richHTML != coordinator.lastHTML { coordinator.replaceContent() }
        if coordinator.lastFontName != font.rawValue || coordinator.lastFontSize != fontSize {
            coordinator.lastFontName = font.rawValue
            coordinator.lastFontSize = fontSize
            DispatchQueue.main.async { [weak coordinator] in coordinator?.applyBaseFont() }
        }
        if let command, command.id != coordinator.lastCommand {
            coordinator.lastCommand = command.id
            DispatchQueue.main.async { [weak coordinator] in coordinator?.apply(command.action) }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: NativeRichTextEditor
        weak var editor: UITextView?
        var lastData: Data?
        var lastHTML: String?
        var lastCommand: UUID?
        var lastFontName: String?
        var lastFontSize: Double = 0
        var isUpdating = false
        init(_ parent: NativeRichTextEditor) { self.parent = parent }
        var baseFont: UIFont {
            let system = UIFont.systemFont(ofSize: parent.fontSize)
            switch parent.font {
            case .rounded: return UIFont(descriptor: system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor, size: parent.fontSize)
            case .serif: return UIFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: parent.fontSize)
            case .mono: return UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            default: return parent.font.familyName.flatMap { UIFont(name: $0, size: parent.fontSize) } ?? system
            }
        }

        func replaceContent() {
            guard let view = editor else { return }
            isUpdating = true
            defer { isUpdating = false }
            let range = view.selectedRange
            if let data = parent.richText,
               let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil), value.string == parent.text {
                view.attributedText = value
            } else if let html = parent.richHTML, let value = RichHTMLBridge.decode(html, matching: parent.text, font: baseFont) {
                view.attributedText = value
            } else { view.attributedText = NSAttributedString(string: parent.text, attributes: [.font: baseFont, .foregroundColor: UIColor(white: 0.14, alpha: 1)]) }
            NoteLinks.refresh(in: view.textStorage)
            let count = (view.text as NSString).length
            view.selectedRange = NSRange(location: min(range.location, count), length: min(range.length, max(0, count - min(range.location, count))))
            view.typingAttributes[.font] = baseFont
            view.typingAttributes = NoteLinks.typingAttributes(from: view.typingAttributes)
            lastData = parent.richText
            lastHTML = parent.richHTML
            lastFontName = parent.font.rawValue
            lastFontSize = parent.fontSize
        }

        func applyBaseFont() {
            guard let view = editor else { return }
            let storage = view.textStorage
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                let traits = ((value as? UIFont)?.fontDescriptor.symbolicTraits ?? []).intersection([.traitBold, .traitItalic])
                let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
                storage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: parent.fontSize), range: range)
            }
            storage.endEditing()
            view.typingAttributes[.font] = baseFont
            lastFontName = parent.font.rawValue
            lastFontSize = parent.fontSize
            publish()
        }

        func textViewDidChange(_ textView: UITextView) { publish() }

        private func link(at point: CGPoint, in view: UITextView) -> URL? {
            let point = CGPoint(x: point.x - view.textContainerInset.left, y: point.y - view.textContainerInset.top)
            let layout = view.layoutManager
            let glyph = layout.glyphIndex(for: point, in: view.textContainer)
            guard glyph < layout.numberOfGlyphs,
                  layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer).contains(point) else { return nil }
            let index = layout.characterIndexForGlyph(at: glyph)
            guard index < view.textStorage.length else { return nil }
            return NoteLinks.safeURL(view.textStorage.attribute(.link, at: index, effectiveRange: nil))
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = editor, view.markedTextRange == nil else { return false }
            return link(at: gestureRecognizer.location(in: view), in: view) != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // UIKit may install selection gestures lazily. Give double-tap word
            // selection priority so a URL can still be selected for editing.
            (otherGestureRecognizer as? UITapGestureRecognizer)?.numberOfTapsRequired ?? 0 > 1
        }

        @objc func openLink(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = editor,
                  let url = link(at: gesture.location(in: view), in: view) else { return }
            UIApplication.shared.open(url)
        }

        func publish() {
            guard !isUpdating, let view = editor else { return }
            isUpdating = true
            defer { isUpdating = false }
            if view.markedTextRange == nil {
                NoteLinks.refresh(in: view.textStorage)
                view.typingAttributes = NoteLinks.typingAttributes(from: view.typingAttributes)
            }
            let data = try? view.attributedText.data(from: NSRange(location: 0, length: view.attributedText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            let html = RichHTMLBridge.encode(view.attributedText)
            lastData = data
            lastHTML = html
            if parent.text != view.text { parent.text = view.text }
            if parent.richText != data { parent.richText = data }
            if parent.richHTML != html { parent.richHTML = html }
        }

        func apply(_ action: RichFormatAction) {
            guard let view = editor else { return }
            view.becomeFirstResponder()
            let range = view.selectedRange
            if action == .bullet || action == .numbered {
                let paragraph = (view.text as NSString).paragraphRange(for: range)
                let lines = (view.text as NSString).substring(with: paragraph).components(separatedBy: "\n")
                let replacement = lines.enumerated().map { index, line in
                    if line.isEmpty && index == lines.count - 1 && index > 0 { return line }
                    return (action == .bullet ? "• " : "\(index + 1). ") + line
                }.joined(separator: "\n")
                if let start = view.position(from: view.beginningOfDocument, offset: paragraph.location),
                   let end = view.position(from: start, offset: paragraph.length),
                   let selected = view.textRange(from: start, to: end) { view.replace(selected, withText: replacement) }
                publish()
                return
            }
            var attributes = range.length == 0 ? view.typingAttributes : view.textStorage.attributes(at: min(range.location, max(0, view.textStorage.length - 1)), effectiveRange: nil)
            if action == .bold || action == .italic {
                let current = attributes[.font] as? UIFont ?? baseFont
                let trait: UIFontDescriptor.SymbolicTraits = action == .bold ? .traitBold : .traitItalic
                var traits = current.fontDescriptor.symbolicTraits
                if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
                attributes[.font] = UIFont(descriptor: current.fontDescriptor.withSymbolicTraits(traits) ?? current.fontDescriptor, size: current.pointSize)
            } else {
                let key: NSAttributedString.Key = action == .underline ? .underlineStyle : .strikethroughStyle
                attributes[key] = (attributes[key] as? Int ?? 0) == 0 ? NSUnderlineStyle.single.rawValue : 0
            }
            if range.length == 0 { view.typingAttributes = attributes }
            else {
                let old = view.textStorage.attributedSubstring(from: range)
                view.undoManager?.registerUndo(withTarget: self) { target in
                    guard let editor = target.editor, NSMaxRange(range) <= editor.textStorage.length else { return }
                    editor.textStorage.replaceCharacters(in: range, with: old)
                    target.publish()
                }
                if action == .bold || action == .italic { view.textStorage.addAttribute(.font, value: attributes[.font]!, range: range) }
                else {
                    let key: NSAttributedString.Key = action == .underline ? .underlineStyle : .strikethroughStyle
                    view.textStorage.addAttribute(key, value: attributes[key]!, range: range)
                }
            }
            publish()
        }
    }
}
#endif
