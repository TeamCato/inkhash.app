import CoreGraphics
import Foundation
import InkhashCore
import PencilKit
import Vision
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum InkDrawing {
    static func empty() -> Data {
        PKDrawing().dataRepresentation()
    }
}

struct PageReading: Equatable {
    var transcript: String
    var tags: [String]
}

enum HandwritingRecognizer {
    /// Rendering and Vision block their thread. They run one page at a time on this queue, never on
    /// the Swift concurrency pool: a notebook opened with many unread pages filled the pool with
    /// waiting threads and froze every task of the app. See P-055.
    private static let queue = DispatchQueue(label: "inkhash.handwriting", qos: .userInitiated)

    /// Reads pen and marker strokes apart: the transcript starts with what the pens wrote, so the
    /// automatic title never comes from a highlight. Marker text follows for search. See ADR 0034.
    static func recognize(drawing: PKDrawing, width: Double, height: Double) async -> PageReading {
        let box = DrawingBox(drawing: drawing)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: readSplit(box.drawing, width: width, height: height))
            }
        }
    }

    private static func readSplit(_ drawing: PKDrawing, width: Double, height: Double) -> PageReading {
        let isMarker: (PKStroke) -> Bool = { $0.ink.inkType == .marker }
        guard drawing.strokes.contains(where: isMarker) else {
            return read(drawing, width: width, height: height)
        }
        let pens = read(PKDrawing(strokes: drawing.strokes.filter { !isMarker($0) }), width: width, height: height)
        let markers = read(PKDrawing(strokes: drawing.strokes.filter(isMarker)), width: width, height: height)
        let transcript = [pens.transcript, markers.transcript].filter { !$0.isEmpty }.joined(separator: "\n")
        return PageReading(transcript: transcript, tags: Hashtags.unique(pens.tags + markers.tags))
    }

    /// Renders the drawing and reads it on device. Language correction stays off so unusual tags survive.
    private static func read(_ drawing: PKDrawing, width: Double, height: Double) -> PageReading {
        if drawing.strokes.isEmpty {
            return PageReading(transcript: "", tags: [])
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let image = rendered(drawing, rect: rect) else {
            return PageReading(transcript: "", tags: [])
        }
        let words = observations(in: image)
        let transcript = Hashtags.transcript(from: words)
        let tags = Hashtags.inObservations(words)
        if transcript.isEmpty, tags.isEmpty {
            return PageReading(transcript: "", tags: [])
        }
        return PageReading(transcript: transcript, tags: tags)
    }

    /// The whole page, in light appearance: PencilKit draws ink for the current appearance, and a
    /// device in dark mode would hand Vision light strokes. Cropped pictures and a white backdrop
    /// read worse in tests, so the page stays whole and transparent. See P-043.
    private static func rendered(_ drawing: PKDrawing, rect: CGRect) -> CGImage? {
        let scale: CGFloat = 2
        #if os(iOS)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image?.cgImage
        #else
        var image: NSImage?
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            image = drawing.image(from: rect, scale: scale)
        }
        guard let image else { return nil }
        var proposed = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        #endif
    }

    private static func observations(in image: CGImage) -> [RecognizedWord] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["de-DE", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let lines = request.results ?? []
        return lines.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            let box = observation.boundingBox
            return RecognizedWord(
                text: text,
                minX: Double(box.minX),
                minY: Double(1 - box.maxY),
                maxX: Double(box.maxX),
                maxY: Double(1 - box.minY)
            )
        }
    }
}

private struct DrawingBox: @unchecked Sendable {
    var drawing: PKDrawing
}
