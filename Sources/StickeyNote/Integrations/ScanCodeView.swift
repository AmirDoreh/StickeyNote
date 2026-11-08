import SwiftUI
import UniformTypeIdentifiers
import Vision
#if os(iOS)
import VisionKit
import AVFoundation
#endif

struct ScanCodeView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var importing = false
    @State private var scanning = false
    @State private var busy = false
    @State private var results: [String] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Scan a code").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            #if os(iOS)
            if scanning {
                LiveCodeScanner(onScan: { value in
                    results = [value]
                    scanning = false
                }, onFailure: { message in error = message; scanning = false })
                .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 16))
                Button("Stop camera") { scanning = false }
            } else if DataScannerViewController.isSupported {
                Button {
                    Task {
                        if await AVCaptureDevice.requestAccess(for: .video) {
                            if DataScannerViewController.isAvailable {
                                scanning = true
                                error = nil
                            } else { error = "Live scanning is unavailable. Choose an image to read its code." }
                        } else { error = "Allow camera access in Settings, or choose an image below." }
                    }
                } label: { Label("Scan with camera", systemImage: "camera.viewfinder") }
                .buttonStyle(.borderedProminent)
            }
            #endif
            Button { importing = true } label: { Label("Choose an image", systemImage: "photo") }
                .buttonStyle(.bordered).disabled(busy)
            Text("Read QR codes and product barcodes. Images are processed on this device.")
                .font(.callout).foregroundStyle(.secondary)
            if busy { ProgressView("Reading code…") }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            ForEach(Array(results.enumerated()), id: \.offset) { _, value in
                VStack(alignment: .leading, spacing: 12) {
                    Text(value).font(.body.monospaced()).textSelection(.enabled)
                        .lineLimit(8).frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Button("Create note") { onScan(value); dismiss() }
                            .buttonStyle(.borderedProminent)
                        if let url = safeWebURL(value) {
                            Button("Open link") { openURL(url) }
                        } else if value.allSatisfy(\.isNumber), value.count >= 6 {
                            Button("Look up barcode") {
                                var components = URLComponents(string: "https://www.google.com/search")!
                                components.queryItems = [URLQueryItem(name: "q", value: value)]
                                if let url = components.url { openURL(url) }
                            }
                        }
                    }
                }
                .padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(24).frame(minWidth: 320, idealWidth: 440)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): readImage(url)
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }

    private func safeWebURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    private func readImage(_ url: URL) {
        busy = true
        error = nil
        Task {
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    let request = VNDetectBarcodesRequest()
                    try VNImageRequestHandler(data: data).perform([request])
                    var seen = Set<String>()
                    return (request.results ?? []).compactMap(\.payloadStringValue)
                        .filter { seen.insert($0).inserted }
                }.value
                results = found
                if found.isEmpty { error = "No readable code found. Try a clear, uncropped image." }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

#if os(iOS)
private struct LiveCodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
                                                  recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                                  isPinchToZoomEnabled: true, isGuidanceEnabled: true,
                                                  isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        do { try controller.startScanning() }
        catch { DispatchQueue.main.async { onFailure(error.localizedDescription) } }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var delivered = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) { deliver([item]) }

        private func deliver(_ items: [RecognizedItem]) {
            guard !delivered else { return }
            for item in items {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    delivered = true
                    onScan(value)
                    return
                }
            }
        }
    }
}
#endif
