import SwiftUI
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Generates a QR code locally; note contents never leave the device.
struct QRCodeView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var exportError: String?

    private var code: CGImage? { QRCodeRenderer.image(for: text) }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Share as QR code").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let code {
                Image(decorative: code, scale: 1)
                    .interpolation(.none).resizable().scaledToFit()
                    .frame(maxWidth: 280, maxHeight: 280)
                    .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityLabel("QR code containing the note text")
                Text("Scan with a camera to open this note’s text.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    ShareLink(item: Image(decorative: code, scale: 1),
                              preview: SharePreview("Note QR code", image: Image(decorative: code, scale: 1))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button { exporting = true } label: { Label("Save PNG", systemImage: "arrow.down.to.line") }
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "qrcode").font(.system(size: 64)).foregroundStyle(.secondary)
                Text(text.isEmpty ? "Add some text to your note first." : "This note is too long for a QR code. Try a shorter selection.")
                    .multilineTextAlignment(.center)
            }
            if let exportError { Text(exportError).font(.caption).foregroundStyle(.red) }
        }
        .padding(28).frame(minWidth: 320, idealWidth: 400)
        .fileExporter(isPresented: $exporting,
                      document: QRPNGDocument(data: QRCodeRenderer.png(for: text) ?? Data()),
                      contentType: .png, defaultFilename: "StickeyNote-QR") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
    }
}

enum QRCodeRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func image(for text: String) -> CGImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Include a standards-compliant four-module quiet zone in exported files.
        let extent = output.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: .white).cropped(to: extent)
        let padded = output.composited(over: white).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        return context.createCGImage(padded, from: padded.extent)
    }

    static func png(for text: String) -> Data? {
        guard let image = image(for: text) else { return nil }
        #if os(macOS)
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        #else
        return UIImage(cgImage: image).pngData()
        #endif
    }
}

private struct QRPNGDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
