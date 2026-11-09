import SwiftUI
import StickeyCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A wrapping checklist field. Its stored value stays plain text; links and
/// completion styling are derived each time the field is displayed or edited.
struct ChecklistTextEditor: View {
    @Binding var text: String
    var font: NoteFont = .system
    var fontSize: Double = 18
    var isCompleted = false
    @Binding var isFocused: Bool
    var onSubmit: () -> Void
    var onDeleteEmpty: () -> Bool = { false }
    var onMove: (Int) -> Void = { _ in }
    var onToggle: () -> Void = {}

    var body: some View {
        NativeChecklistTextEditor(text: $text, font: font, fontSize: fontSize, isCompleted: isCompleted,
                                  isFocused: $isFocused, onSubmit: onSubmit, onDeleteEmpty: onDeleteEmpty,
                                  onMove: onMove, onToggle: onToggle)
            .frame(maxWidth: .infinity, minHeight: fontSize * 1.2 + 2, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("New item").noteFont(font, size: fontSize)
                        .foregroundStyle(Color.black.opacity(0.35))
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .alignmentGuide(.firstTextBaseline) { _ in fontSize * 0.85 + 1 }
            .accessibilityLabel("Checklist item")
    }
}

#if os(macOS)
private struct NativeChecklistTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NoteFont
    var fontSize: Double
    var isCompleted: Bool
    @Binding var isFocused: Bool
    var onSubmit: () -> Void
    var onDeleteEmpty: () -> Bool
    var onMove: (Int) -> Void
    var onToggle: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ChecklistNSTextView {
        let view = ChecklistNSTextView()
        view.delegate = context.coordinator
        view.appearance = NSAppearance(named: .aqua)
        view.drawsBackground = false
        view.isRichText = false
        view.isEditable = true
        view.isSelectable = true
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainerInset = NSSize(width: 0, height: 1)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        view.insertionPointColor = NSColor(calibratedWhite: 0.14, alpha: 1)
        view.linkTextAttributes = [.foregroundColor: NSColor.systemBlue,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .cursor: NSCursor.pointingHand]
        view.displaysLinkToolTips = true
        view.setAccessibilityLabel("Checklist item")
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.onSubmit = { [weak coordinator = context.coordinator] in coordinator?.parent.onSubmit() }
        view.onDeleteEmpty = { [weak coordinator = context.coordinator] in coordinator?.parent.onDeleteEmpty() ?? false }
        view.onMove = { [weak coordinator = context.coordinator] in coordinator?.parent.onMove($0) }
        view.onToggle = { [weak coordinator = context.coordinator] in coordinator?.parent.onToggle() }
        view.onFocusChange = { [weak coordinator = context.coordinator] focused in coordinator?.updateFocus(focused) }
        view.onAttach = { [weak coordinator = context.coordinator] in coordinator?.applyFocus() }
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.openLink(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        click.delegate = context.coordinator
        view.addGestureRecognizer(click)
        context.coordinator.editor = view
        context.coordinator.updateContent()
        return view
    }

    func updateNSView(_ view: ChecklistNSTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateContent()
        context.coordinator.applyFocus()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChecklistNSTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? nsView.bounds.width)
        return CGSize(width: width, height: nsView.contentHeight(for: width))
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSGestureRecognizerDelegate {
        var parent: NativeChecklistTextEditor
        weak var editor: ChecklistNSTextView?
        var isUpdating = false
        private var lastOpenedURL: URL?
        private var lastOpenedAt: TimeInterval = 0
        init(_ parent: NativeChecklistTextEditor) { self.parent = parent }

        var baseFont: NSFont {
            let system = NSFont.systemFont(ofSize: parent.fontSize)
            switch parent.font {
            case .rounded: return NSFont(descriptor: system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor, size: parent.fontSize) ?? system
            case .serif: return NSFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: parent.fontSize) ?? system
            case .mono: return NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            default: return parent.font.familyName.flatMap { NSFont(name: $0, size: parent.fontSize) } ?? system
            }
        }

        var attributes: [NSAttributedString.Key: Any] {
            [.font: baseFont, .foregroundColor: NSColor(calibratedWhite: 0.14, alpha: parent.isCompleted ? 0.45 : 1),
             .strikethroughStyle: parent.isCompleted ? NSUnderlineStyle.single.rawValue : 0]
        }

        func updateContent() {
            guard !isUpdating, let view = editor, !view.hasMarkedText(), let storage = view.textStorage else { return }
            isUpdating = true
            defer { isUpdating = false }
            if view.string != parent.text {
                let selection = view.selectedRange()
                storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: parent.text)
                let start = min(selection.location, storage.length)
                view.setSelectedRange(NSRange(location: start, length: min(selection.length, storage.length - start)))
            }
            style(view)
        }

        func style(_ view: ChecklistNSTextView) {
            guard let storage = view.textStorage else { return }
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            NoteLinks.refresh(in: storage)
            storage.endEditing()
            view.typingAttributes = attributes
            view.invalidateIntrinsicContentSize()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let view = editor else { return }
            isUpdating = true
            if !view.hasMarkedText() { style(view) }
            if parent.text != view.string { parent.text = view.string }
            isUpdating = false
        }

        func updateFocus(_ focused: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.editor,
                      (view.window?.firstResponder === view) == focused else { return }
                if self.parent.isFocused != focused { self.parent.isFocused = focused }
            }
        }

        func applyFocus() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.editor, let window = view.window else { return }
                if self.parent.isFocused && window.firstResponder !== view { window.makeFirstResponder(view) }
                else if !self.parent.isFocused && window.firstResponder === view { window.makeFirstResponder(nil) }
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            guard let view = editor, !view.hasMarkedText(),
                  NSEvent.modifierFlags.intersection([.shift, .option, .control, .command]).isEmpty else { return false }
            return view.link(at: gestureRecognizer.location(in: view)) != nil
        }

        @objc func openLink(_ gesture: NSClickGestureRecognizer) {
            guard gesture.state == .ended, let view = editor,
                  let url = view.link(at: gesture.location(in: view)) else { return }
            openURL(url)
        }

        // The click recognizer supplies direct opening without disabling normal
        // caret placement, selection dragging, or Option-click editing.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = NoteLinks.safeURL(link) { openURL(url) }
            return true
        }

        private func openURL(_ url: URL) {
            // AppKit can report the same click through its native link action
            // and our recognizer. Keep context-menu/accessibility actions too.
            let now = ProcessInfo.processInfo.systemUptime
            guard url != lastOpenedURL || now - lastOpenedAt >= 0.3 else { return }
            lastOpenedURL = url
            lastOpenedAt = now
            NSWorkspace.shared.open(url)
        }
    }
}

private final class ChecklistNSTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var onDeleteEmpty: () -> Bool = { false }
    var onMove: (Int) -> Void = { _ in }
    var onToggle: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var onAttach: () -> Void = {}

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight(for: max(1, bounds.width)))
    }

    func contentHeight(for width: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else { return 22 }
        textContainer.containerSize = NSSize(width: max(1, width - 2 * textContainerInset.width), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let minimum = layoutManager.defaultLineHeight(for: font ?? NSFont.systemFont(ofSize: 18))
        return ceil(max(minimum, layoutManager.usedRect(for: textContainer).maxY,
                        layoutManager.extraLineFragmentRect.maxY) + 2 * textContainerInset.height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.width != newSize.width
        super.setFrameSize(newSize)
        if changed { invalidateIntrinsicContentSize() }
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onAttach() }
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange(true) }
        return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange(false) }
        return result
    }

    override func keyDown(with event: NSEvent) {
        if !hasMarkedText() {
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if [36, 76].contains(event.keyCode) {
                if modifiers == .command { onToggle(); return }
                if modifiers.isEmpty { onSubmit(); return }
            }
            if modifiers == .command && [125, 126].contains(event.keyCode) {
                onMove(event.keyCode == 126 ? -1 : 1); return
            }
            if [51, 117].contains(event.keyCode), modifiers.intersection([.command, .option, .control]).isEmpty,
               string.isEmpty, onDeleteEmpty() { return }
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        insertText(value, replacementRange: selectedRange())
    }

    func link(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        let point = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(point) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < textStorage.length else { return nil }
        return NoteLinks.safeURL(textStorage.attribute(.link, at: index, effectiveRange: nil))
    }
}
#else
private struct NativeChecklistTextEditor: UIViewRepresentable {
    @Binding var text: String
    var font: NoteFont
    var fontSize: Double
    var isCompleted: Bool
    @Binding var isFocused: Bool
    var onSubmit: () -> Void
    var onDeleteEmpty: () -> Bool
    var onMove: (Int) -> Void
    var onToggle: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ChecklistUITextView {
        let view = ChecklistUITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.overrideUserInterfaceStyle = .light
        view.isScrollEnabled = false
        view.isEditable = true
        view.isSelectable = true
        view.allowsEditingTextAttributes = false
        view.textContainerInset = UIEdgeInsets(top: 1, left: 0, bottom: 1, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.tintColor = UIColor(white: 0.14, alpha: 1)
        view.linkTextAttributes = [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.accessibilityLabel = "Checklist item"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.onDeleteEmpty = { [weak coordinator = context.coordinator] in coordinator?.parent.onDeleteEmpty() ?? false }
        view.onMove = { [weak coordinator = context.coordinator] in coordinator?.parent.onMove($0) }
        view.onToggle = { [weak coordinator = context.coordinator] in coordinator?.parent.onToggle() }
        view.onAttach = { [weak coordinator = context.coordinator] in coordinator?.applyFocus() }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.openLink(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.editor = view
        context.coordinator.updateContent()
        return view
    }

    func updateUIView(_ view: ChecklistUITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateContent()
        context.coordinator.applyFocus()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ChecklistUITextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? uiView.bounds.width)
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: NativeChecklistTextEditor
        weak var editor: ChecklistUITextView?
        var isUpdating = false
        init(_ parent: NativeChecklistTextEditor) { self.parent = parent }

        var baseFont: UIFont {
            let system = UIFont.systemFont(ofSize: parent.fontSize)
            switch parent.font {
            case .rounded: return UIFont(descriptor: system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor, size: parent.fontSize)
            case .serif: return UIFont(descriptor: system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor, size: parent.fontSize)
            case .mono: return UIFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            default: return parent.font.familyName.flatMap { UIFont(name: $0, size: parent.fontSize) } ?? system
            }
        }

        var attributes: [NSAttributedString.Key: Any] {
            [.font: baseFont, .foregroundColor: UIColor(white: 0.14, alpha: parent.isCompleted ? 0.45 : 1),
             .strikethroughStyle: parent.isCompleted ? NSUnderlineStyle.single.rawValue : 0]
        }

        func updateContent() {
            guard !isUpdating, let view = editor, view.markedTextRange == nil else { return }
            isUpdating = true
            defer { isUpdating = false }
            if view.text != parent.text {
                let selection = view.selectedRange
                view.text = parent.text
                let start = min(selection.location, view.textStorage.length)
                view.selectedRange = NSRange(location: start, length: min(selection.length, view.textStorage.length - start))
            }
            style(view)
        }

        func style(_ view: ChecklistUITextView) {
            view.textStorage.beginEditing()
            view.textStorage.setAttributes(attributes, range: NSRange(location: 0, length: view.textStorage.length))
            NoteLinks.refresh(in: view.textStorage)
            view.textStorage.endEditing()
            view.typingAttributes = attributes
            view.invalidateIntrinsicContentSize()
        }

        func textViewDidChange(_ view: UITextView) {
            guard !isUpdating, let view = view as? ChecklistUITextView else { return }
            isUpdating = true
            if view.markedTextRange == nil { style(view) }
            if parent.text != view.text { parent.text = view.text }
            isUpdating = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", textView.markedTextRange == nil, editor?.insertingLineBreak != true {
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidBeginEditing(_ textView: UITextView) { if !parent.isFocused { parent.isFocused = true } }
        func textViewDidEndEditing(_ textView: UITextView) { if parent.isFocused { parent.isFocused = false } }

        func applyFocus() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.editor, view.window != nil else { return }
                if self.parent.isFocused && !view.isFirstResponder { view.becomeFirstResponder() }
                else if !self.parent.isFocused && view.isFirstResponder { view.resignFirstResponder() }
            }
        }

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
            // Keep double-tap word selection available when editing a URL.
            (otherGestureRecognizer as? UITapGestureRecognizer)?.numberOfTapsRequired ?? 0 > 1
        }

        @objc func openLink(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = editor, let url = link(at: gesture.location(in: view), in: view) else { return }
            UIApplication.shared.open(url)
        }
    }
}

private final class ChecklistUITextView: UITextView {
    var onDeleteEmpty: () -> Bool = { false }
    var onMove: (Int) -> Void = { _ in }
    var onToggle: () -> Void = {}
    var onAttach: () -> Void = {}
    var insertingLineBreak = false

    override func didMoveToWindow() { super.didMoveToWindow(); onAttach() }

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(insertLineBreak)),
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(toggleItem)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: .command, action: #selector(moveUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: .command, action: #selector(moveDown))
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return (super.keyCommands ?? []) + commands
    }

    @objc private func insertLineBreak() { insertingLineBreak = true; insertText("\n"); insertingLineBreak = false }
    @objc private func toggleItem() { onToggle() }
    @objc private func moveUp() { onMove(-1) }
    @objc private func moveDown() { onMove(1) }

    override func deleteBackward() {
        if markedTextRange == nil, text.isEmpty, onDeleteEmpty() { return }
        super.deleteBackward()
    }

    override func paste(_ sender: Any?) {
        guard let value = UIPasteboard.general.string else { return }
        // A pasted newline belongs to this item, unlike pressing Return.
        insertingLineBreak = true
        insertText(value)
        insertingLineBreak = false
    }
}
#endif
