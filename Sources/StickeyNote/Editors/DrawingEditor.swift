import SwiftUI
import UniformTypeIdentifiers
import StickeyCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct DrawingEditor: View {
    @Binding var strokes: [DrawingStroke]
    var backgroundText: String? = nil
    var font: NoteFont = .system
    var fontSize: Double = 18
    @State private var ink = "252525"
    @State private var width = 3.0
    @State private var isErasing = false
    @State private var currentPoints: [DrawingPoint] = []
    @State private var undoStack: [[DrawingStroke]] = []
    @State private var redoStack: [[DrawingStroke]] = []
    @State private var gestureStart: [DrawingStroke]?
    @State private var showClear = false
    @State private var showExporter = false
    @State private var exportDocument = DrawingPNGDocument(data: Data())
    @State private var exportError: String?
    @State private var canvasSize = CGSize(width: 600, height: 400)

    var body: some View {
        VStack(spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { penControls; Spacer(minLength: 0); actionControls }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { penControls; Spacer(minLength: 0) }
                    HStack { Spacer(); actionControls }
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(Color.black.opacity(0.65))

            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.24))
                    Canvas { context, size in
                        for x in stride(from: 14.0, to: size.width, by: 22) {
                            for y in stride(from: 14.0, to: size.height, by: 22) {
                                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.1, height: 1.1)), with: .color(.black.opacity(0.1)))
                            }
                        }
                    }
                    EditorDrawingPage(strokes: strokes, backgroundText: backgroundText, font: font, fontSize: fontSize).equatable()
                    if !currentPoints.isEmpty {
                        EditorDrawingPreview(strokes: [DrawingStroke(points: currentPoints, color: ink, width: width)])
                    }
                    if strokes.isEmpty && currentPoints.isEmpty && (backgroundText?.isEmpty ?? true) {
                        VStack(spacing: 8) {
                            Image(systemName: "pencil.tip.crop.circle").font(.system(size: 32, weight: .ultraLight))
                            Text("A little space to think out loud.").font(.system(size: 13))
                            Text("Draw with your finger, pencil, or mouse.").font(.system(size: 11))
                        }
                        .foregroundStyle(Color.black.opacity(0.3))
                        .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if gestureStart == nil { gestureStart = strokes }
                        let point = DrawingPoint(x: min(1, max(0, value.location.x / max(1, geometry.size.width))), y: min(1, max(0, value.location.y / max(1, geometry.size.height))))
                        if isErasing { erase(at: point, size: geometry.size) }
                        else {
                            if let previous = currentPoints.last,
                               abs(previous.x - point.x) + abs(previous.y - point.y) < 0.001 { return }
                            currentPoints.append(point)
                        }
                    }
                    .onEnded { _ in
                        if !isErasing && !currentPoints.isEmpty {
                            strokes.append(DrawingStroke(points: currentPoints, color: ink, width: width))
                        }
                        if let old = gestureStart, old != strokes { remember(old) }
                        currentPoints = []
                        gestureStart = nil
                    })
                .accessibilityLabel("Drawing canvas")
                .accessibilityHint("Drag to draw. Choose the eraser to remove strokes.")
                .onAppear { canvasSize = geometry.size }
                .onChange(of: geometry.size) { _, size in canvasSize = size }
            }
            .frame(minHeight: 260, idealHeight: 370, maxHeight: .infinity)
        }
        .confirmationDialog("Clear this drawing?", isPresented: $showClear, titleVisibility: .visible) {
            Button("Clear drawing", role: .destructive) { remember(strokes); strokes = [] }
        } message: { Text("You can undo this while the drawing editor is open.") }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .png, defaultFilename: "StickeyNote Drawing") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("Couldn’t export drawing", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var penControls: some View {
        HStack(spacing: 9) {
            ForEach(["252525", "386FDB", "E25554"], id: \.self) { value in
                Button { ink = value; isErasing = false } label: {
                    Circle().fill(drawingColor(value)).frame(width: 22, height: 22)
                        .padding(4)
                        .overlay(Circle().strokeBorder(drawingColor(value).opacity(ink == value && !isErasing ? 0.7 : 0), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value == "252525" ? "Black pen" : value == "386FDB" ? "Blue pen" : "Red pen")
                .accessibilityAddTraits(ink == value && !isErasing ? .isSelected : [])
            }
            Button { isErasing.toggle() } label: {
                Image(systemName: "eraser").frame(width: 30, height: 30)
                    .background(isErasing ? Color.black.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain).help("Eraser").accessibilityLabel("Eraser")
            .accessibilityAddTraits(isErasing ? .isSelected : [])
            Slider(value: $width, in: 1...10).frame(minWidth: 40, maxWidth: 90)
                .tint(Color.black.opacity(0.55))
                .accessibilityLabel("Pen width").accessibilityValue("\(Int(width)) points")
        }
    }

    private var actionControls: some View {
        HStack(spacing: 6) {
            tool("Undo stroke", symbol: "arrow.uturn.backward", disabled: undoStack.isEmpty) { undo() }
            tool("Redo stroke", symbol: "arrow.uturn.forward", disabled: redoStack.isEmpty) { redo() }
            tool("Export drawing", symbol: "square.and.arrow.up", disabled: strokes.isEmpty) { exportPNG() }
            tool("Clear drawing", symbol: "trash", disabled: strokes.isEmpty) { showClear = true }
        }
    }

    private func tool(_ title: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 30) }
            .buttonStyle(.plain).disabled(disabled).help(title).accessibilityLabel(title)
            .opacity(disabled ? 0.3 : 1)
    }

    private func remember(_ previous: [DrawingStroke]) {
        undoStack.append(previous)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }

    private func erase(at point: DrawingPoint, size: CGSize) {
        let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
        strokes.removeAll { stroke in
            let points = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            guard !points.isEmpty else { return false }
            let threshold = 12 + stroke.width / 2
            if points.count == 1 { return hypot(points[0].x - position.x, points[0].y - position.y) < threshold }
            for index in 1..<points.count {
                let a = points[index - 1], b = points[index]
                let dx = b.x - a.x, dy = b.y - a.y
                let length = dx * dx + dy * dy
                let t = length == 0 ? 0 : max(0, min(1, ((position.x - a.x) * dx + (position.y - a.y) * dy) / length))
                if hypot(a.x + t * dx - position.x, a.y + t * dy - position.y) < threshold { return true }
            }
            return false
        }
    }

    @MainActor private func exportPNG() {
        let height = min(2400, max(200, 1200 * canvasSize.height / max(1, canvasSize.width)))
        let scale = 1200 / max(1, canvasSize.width)
        let renderer = ImageRenderer(content: EditorDrawingPage(strokes: strokes, backgroundText: backgroundText, font: font, fontSize: fontSize, textScale: scale).frame(width: 1200, height: height).background(.white))
        renderer.scale = 1
        #if os(macOS)
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            exportError = "The drawing image could not be created."
            return
        }
        #else
        guard let data = renderer.uiImage?.pngData() else {
            exportError = "The drawing image could not be created."
            return
        }
        #endif
        exportDocument = DrawingPNGDocument(data: data)
        showExporter = true
    }
}

/// Keep the text and ink in the same coordinate space for editing and export.
private struct EditorDrawingPage: View, Equatable {
    var strokes: [DrawingStroke]
    var backgroundText: String?
    var font: NoteFont
    var fontSize: Double
    var textScale: Double = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let backgroundText, !backgroundText.isEmpty {
                Text(backgroundText)
                    .font(textFont)
                    .lineSpacing(5 * textScale)
                    .foregroundStyle(Color.black.opacity(0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(18 * textScale)
            }
            EditorDrawingPreview(strokes: strokes)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var textFont: Font {
        let size = fontSize * textScale
        switch font {
        case .rounded: return .system(size: size, design: .rounded)
        case .serif: return .system(size: size, design: .serif)
        case .mono: return .system(size: size, design: .monospaced)
        default: return font.familyName.map { .custom($0, size: size) } ?? .system(size: size)
        }
    }
}

/// Lightweight canvas used for both the editor and card previews.
private struct EditorDrawingPreview: View, Equatable {
    var strokes: [DrawingStroke]

    var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                let lineWidth = stroke.width * size.width / 600
                var path = Path()
                path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                if stroke.points.count == 1 {
                    path.addEllipse(in: CGRect(x: first.x * size.width - lineWidth / 2, y: first.y * size.height - lineWidth / 2, width: lineWidth, height: lineWidth))
                    context.fill(path, with: .color(drawingColor(stroke.color)))
                } else {
                    for point in stroke.points.dropFirst() { path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height)) }
                    context.stroke(path, with: .color(drawingColor(stroke.color)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private func drawingColor(_ hex: String) -> Color {
    let value = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x252525
    return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
}

private struct DrawingPNGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
