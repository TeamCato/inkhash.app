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
    /// Drawn boxes with the line beside them. See ADR 0060.
    var tasks: [InkTask] = []
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

    /// Drawn boxes and their ticks are taken out first: they are tasks, not words. See ADR 0060.
    private static func readSplit(_ drawing: PKDrawing, width: Double, height: Double) -> PageReading {
        let isMarker: (PKStroke) -> Bool = { $0.ink.inkType == .marker }
        let pens = drawing.strokes.filter { !isMarker($0) }
        let marks = TaskBoxes.marks(in: pens.map(InkTasks.points(of:)))
        let writing = pens.enumerated().filter { !marks.strokes.contains($0.offset) }.map(\.element)
        let (penReading, lines) = read(PKDrawing(strokes: writing), width: width, height: height)
        let tasks = TaskBoxes.tasks(marks, lines: lines, size: CGSize(width: width, height: height))
        let markers = drawing.strokes.filter(isMarker)
        guard !markers.isEmpty else {
            return PageReading(transcript: penReading.transcript, tags: penReading.tags, tasks: tasks)
        }
        let markerReading = read(PKDrawing(strokes: markers), width: width, height: height).reading
        let transcript = [penReading.transcript, markerReading.transcript].filter { !$0.isEmpty }.joined(separator: "\n")
        return PageReading(transcript: transcript, tags: Hashtags.unique(penReading.tags + markerReading.tags), tasks: tasks)
    }

    /// Renders the drawing and reads it on device. Language correction stays off so unusual tags survive.
    /// The recognized lines come along for the tasks beside drawn boxes.
    private static func read(_ drawing: PKDrawing, width: Double, height: Double) -> (reading: PageReading, lines: [RecognizedWord]) {
        let empty = (PageReading(transcript: "", tags: []), [RecognizedWord]())
        if drawing.strokes.isEmpty { return empty }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let image = rendered(drawing, rect: rect) else { return empty }
        let words = observations(in: image)
        let transcript = Hashtags.transcript(from: words)
        let tags = Hashtags.inObservations(words)
        if transcript.isEmpty, tags.isEmpty { return empty }
        return (PageReading(transcript: transcript, tags: tags), words)
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
