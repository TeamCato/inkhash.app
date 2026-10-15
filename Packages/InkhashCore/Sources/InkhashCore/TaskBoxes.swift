import CoreGraphics
import Foundation

/// Finds tasks on a handwriting page: a small box drawn in one stroke, ticked by any stroke inside
/// it, with the recognized line to its right as its text. Pure geometry, so it runs without PencilKit.
/// See ADR 0060.
public enum TaskBoxes {
    /// Side lengths a box may have, in page points. Smaller is a dot, larger a frame in a sketch.
    static let sides: ClosedRange<CGFloat> = 8...60

    /// Boxes and their ticks among the strokes, each stroke given as its points in page coordinates.
    public struct Marks: Equatable, Sendable {
        public var boxes: [CGRect]
        public var ticked: [Bool]
        /// Indices of the strokes that are boxes or ticks. They stay out of the transcript.
        public var strokes: Set<Int>
    }

    public static func marks(in strokes: [[CGPoint]]) -> Marks {
        var boxes: [(index: Int, rect: CGRect)] = []
        for (index, points) in strokes.enumerated() {
            if let rect = box(points) { boxes.append((index, rect)) }
        }
        var used = Set(boxes.map(\.index))
        var ticked = Array(repeating: false, count: boxes.count)
        for (index, points) in strokes.enumerated() where !used.contains(index) {
            guard let bounds = bounds(of: points) else { continue }
            if let owner = boxes.firstIndex(where: { isTick(bounds, in: $0.rect) }) {
                ticked[owner] = true
                used.insert(index)
            }
        }
        return Marks(boxes: boxes.map(\.rect), ticked: ticked, strokes: used)
    }

    /// The tasks for the boxes that have a line beside them. `lines` are recognized lines in
    /// normalized coordinates over a page of `size`.
    public static func tasks(_ marks: Marks, lines: [RecognizedWord], size: CGSize) -> [InkTask] {
        zip(marks.boxes, marks.ticked).compactMap { box, ticked in
            guard let text = line(beside: box, in: lines, size: size) else { return nil }
            return InkTask(
                x: Double(box.minX), y: Double(box.minY), width: Double(box.width), height: Double(box.height),
                text: text, checked: ticked
            )
        }
        .sorted { lhs, rhs in
            abs(lhs.y - rhs.y) > min(lhs.height, rhs.height) / 2 ? lhs.y < rhs.y : lhs.x < rhs.x
        }
    }

    /// A single closed stroke, about square, with sharp corners: not an O, not a D, not a frame.
    public static func box(_ points: [CGPoint]) -> CGRect? {
        guard points.count >= 8, let rect = bounds(of: points) else { return nil }
        let short = min(rect.width, rect.height)
        let long = max(rect.width, rect.height)
        guard sides.contains(short), sides.contains(long), long / short <= 1.6 else { return nil }
        guard let first = points.first, let last = points.last, distance(first, last) <= 0.35 * long else { return nil }
        let perimeter = 2 * (rect.width + rect.height)
        let length = zip(points, points.dropFirst()).reduce(CGFloat(0)) { $0 + distance($1.0, $1.1) }
        guard length >= 0.85 * perimeter, length <= 1.6 * perimeter else { return nil }
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
        // A circle's nearest point to a corner of its bounds lies about 0.21 of the side away.
        let reach = 0.17 * short
        for corner in corners where !points.contains(where: { distance($0, corner) <= reach }) {
            return nil
        }
        // Most of the path runs along the edges, not through the middle.
        let band = 0.2 * short
        let onEdges = points.filter { point in
            min(point.x - rect.minX, rect.maxX - point.x, point.y - rect.minY, rect.maxY - point.y) <= band
        }
        guard Double(onEdges.count) >= 0.8 * Double(points.count) else { return nil }
        return rect
    }

    /// Indices of the strokes that tick `box`: on it and not a box themselves.
    public static func ticks(in strokes: [[CGPoint]], box: CGRect) -> [Int] {
        strokes.indices.filter { index in
            guard self.box(strokes[index]) == nil, let bounds = bounds(of: strokes[index]) else { return false }
            return isTick(bounds, in: box)
        }
    }

    /// A tick sits on the box: its middle inside, not much larger than the box. Ticks overshoot.
    static func isTick(_ bounds: CGRect, in box: CGRect) -> Bool {
        let reach = box.insetBy(dx: -box.width * 0.25, dy: -box.height * 0.25)
        guard reach.contains(CGPoint(x: bounds.midX, y: bounds.midY)) else { return false }
        return bounds.width <= box.width * 2.2 && bounds.height <= box.height * 2.2
    }

    /// The nearest recognized line right of the box whose height covers the box's middle.
    static func line(beside box: CGRect, in lines: [RecognizedWord], size: CGSize) -> String? {
        let candidates = lines.compactMap { word -> (gap: CGFloat, text: String)? in
            let minX = CGFloat(word.minX) * size.width
            let minY = CGFloat(word.minY) * size.height
            let maxY = CGFloat(word.maxY) * size.height
            let slack = box.height * 0.3
            guard minX >= box.midX, minY - slack <= box.midY, maxY + slack >= box.midY else { return nil }
            let gap = minX - box.maxX
            guard gap <= box.height * 4 else { return nil }
            let text = word.text.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (gap, text)
        }
        return candidates.min { $0.gap < $1.gap }?.text
    }

    static func bounds(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Points of a tick drawn into `box`, in page coordinates: down to the lower third, up to the far corner.
    public static func tick(in box: CGRect) -> [CGPoint] {
        let start = CGPoint(x: box.minX + box.width * 0.2, y: box.minY + box.height * 0.55)
        let bottom = CGPoint(x: box.minX + box.width * 0.42, y: box.minY + box.height * 0.8)
        let end = CGPoint(x: box.minX + box.width * 0.85, y: box.minY + box.height * 0.18)
        return segment(start, bottom, steps: 6) + segment(bottom, end, steps: 10).dropFirst()
    }

    private static func segment(_ from: CGPoint, _ to: CGPoint, steps: Int) -> [CGPoint] {
        (0...steps).map { step in
            let t = CGFloat(step) / CGFloat(steps)
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
