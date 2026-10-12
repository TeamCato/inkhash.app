import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import InkhashCore
import SwiftUI
import Vision

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Draws a text as a QR code, sharp at any size.
struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .aspectRatio(1, contentMode: .fit)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("QR-Code zum Koppeln")
        } else {
            Text("Der QR-Code ließ sich nicht erzeugen.").foregroundStyle(Ink.muted)
        }
    }

    static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

/// Reads the first QR code the camera sees that `accepts` takes; others are passed over. Capture
/// and recognition run on one private queue; the found text comes out of `codes` once. See ADR 0054.
final class QRScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    // @unchecked: `delivered` is only touched on `queue`, the session is configured there too.
    let session = AVCaptureSession()
    let codes: AsyncStream<String>
    private let found: AsyncStream<String>.Continuation
    private let queue = DispatchQueue(label: "inkhash.qr-scanner")
    private var delivered = false
    private let accepts: @Sendable (String) -> Bool

    init(accepts: @escaping @Sendable (String) -> Bool) {
        self.accepts = accepts
        (codes, found) = AsyncStream.makeStream(of: String.self)
        super.init()
    }

    /// Whether this device has a camera at all. Without one, the recovery key is the way in.
    static var hasCamera: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    /// Asks for the camera and starts. Nil once running, else why not, for the sheet.
    func start() async -> String? {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return Self.denied }
        default:
            return Self.denied
        }
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera) else { return "Keine Kamera gefunden." }
        return await withCheckedContinuation { continuation in
            queue.async {
                self.delivered = false
                self.session.beginConfiguration()
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.queue)
                guard self.session.canAddInput(input), self.session.canAddOutput(output) else {
                    self.session.commitConfiguration()
                    continuation.resume(returning: "Die Kamera ließ sich nicht öffnen.")
                    return
                }
                self.session.addInput(input)
                self.session.addOutput(output)
                self.session.commitConfiguration()
                self.session.startRunning()
                continuation.resume(returning: nil)
            }
        }
    }

    func stop() {
        found.finish()
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !delivered, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cvPixelBuffer: pixels).perform([request])
        guard let text = request.results?.lazy.compactMap(\.payloadStringValue).first(where: accepts) else { return }
        delivered = true
        found.yield(text)
        found.finish()
    }

    private static let denied = "Inkhash darf die Kamera nicht benutzen. Das lässt sich in den Systemeinstellungen ändern."
}

/// The camera's picture, filling its frame.
struct CameraPreview: View {
    let session: AVCaptureSession

    var body: some View {
        PreviewLayerView(session: session)
            .background(Color.black)
    }
}

#if os(macOS)
private struct PreviewLayerView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        PreviewNSView(session: session)
    }

    func updateNSView(_ view: PreviewNSView, context: Context) {}
}

private final class PreviewNSView: NSView {
    private let preview: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        preview.frame = bounds
    }
}
#else
private struct PreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {}
}

private final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
#endif

/// Scans a pairing code and hands it on. The caller opens the vault with it. See ADR 0054.
struct QRScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCode: (String) -> Void
    @State private var scanner = QRScanner(accepts: Pairing.isCode)
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreview(session: scanner.session)
                    .ignoresSafeArea()
                if let problem {
                    Text(problem)
                        .multilineTextAlignment(.center)
                        .padding(20)
                        .inkPanel()
                        .padding(24)
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 240, height: 240)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle("QR-Code scannen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .macSheetSize(minWidth: 480, minHeight: 420)
        .task {
            problem = await scanner.start()
            guard problem == nil else { return }
            for await code in scanner.codes {
                onCode(code)
                dismiss()
                break
            }
        }
        .onDisappear { scanner.stop() }
    }
}
