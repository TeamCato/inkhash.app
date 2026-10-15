import CoreGraphics
import Foundation

/// Finds tasks on a handwriting page: a small box drawn in one stroke or a few in a row, ticked by any stroke inside
/// it, with the recognized line to its right as its text. Pure geometry, so it runs without PencilKit.
/// See ADR 0060 and 0065.
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

    /// A box may be drawn in up to this many strokes in a row, such as "∩" and then the bottom.
    static let maxParts = 4

    public static func marks(in strokes: [[CGPoint]]) -> Marks {
        let boxes = groups(in: strokes)
        var used = Set(boxes.flatMap(\.strokes))
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

    /// Boxes in drawing order, each from one stroke or a few drawn one after another. The fewest
    /// strokes that make a box win, so a tick drawn right after its box stays a tick.
    static func groups(in strokes: [[CGPoint]]) -> [(strokes: Range<Int>, rect: CGRect)] {
        var found: [(strokes: Range<Int>, rect: CGRect)] = []
        var start = 0
        scan: while start < strokes.count {
            for count in 1...maxParts where start + count <= strokes.count {
                let range = start..<(start + count)
                let rect = count == 1 ? box(strokes[start]) : box(parts: Array(strokes[range]))
                if let rect {
                    found.append((range, rect))
                    start = range.upperBound
                    continue scan
                }
            }
            start += 1
        }
        return found
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

    /// A box from several strokes: they close in an area of box size that fills its corners about
    /// as a box does, every stroke runs along its edge, and one of them is a straight line along
    /// the top or bottom. That line keeps out an O in two strokes and a D, whose straight stem stands upright.
    static func box(parts: [[CGPoint]]) -> CGRect? {
        let points = parts.flatMap { $0 }
        guard points.count >= 8, let bounds = bounds(of: points) else { return nil }
        guard min(bounds.width, bounds.height) >= sides.lowerBound, max(bounds.width, bounds.height) <= sides.upperBound * 1.5 else { return nil }
        let radius = max(1.5, 0.08 * min(bounds.width, bounds.height))
        guard let area = EnclosedArea.largest(in: parts, inkRadius: radius) else { return nil }
        let rect = area.rect
        let short = min(rect.width, rect.height)
        let long = max(rect.width, rect.height)
        guard sides.contains(short), sides.contains(long), long / short <= 1.6 else { return nil }
        guard area.fill >= 0.7, area.size >= 0.35 * Double(bounds.width * bounds.height) else { return nil }
        let band = 0.25 * short
        for part in parts {
            let onEdge = part.filter { distance($0, toEdgeOf: rect) <= band }
            guard Double(onEdge.count) >= 0.6 * Double(part.count) else { return nil }
        }
        guard parts.contains(where: { isBase($0, of: rect, band: band) }) else { return nil }
        return rect
    }

    /// A straight, level stroke along the top or bottom of `rect`, over most of its width.
    static func isBase(_ points: [CGPoint], of rect: CGRect, band: CGFloat) -> Bool {
        guard let first = points.first, let last = points.last else { return false }
        let length = distance(first, last)
        guard length >= 0.6 * rect.width, abs(last.y - first.y) <= 0.35 * abs(last.x - first.x) else { return false }
        let straight = points.allSatisfy { point in
            abs((last.x - first.x) * (first.y - point.y) - (first.x - point.x) * (last.y - first.y)) / length <= 0.2 * length
        }
        let middle = (first.y + last.y) / 2
        return straight && min(abs(middle - rect.minY), abs(middle - rect.maxY)) <= band
    }

    /// Distance from a point to the outline of `rect`, from inside or outside.
    static func distance(_ point: CGPoint, toEdgeOf rect: CGRect) -> CGFloat {
        if rect.contains(point) {
            return min(point.x - rect.minX, rect.maxX - point.x, point.y - rect.minY, rect.maxY - point.y)
        }
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Indices of the strokes that tick `box`: on it and not part of a box themselves.
    public static func ticks(in strokes: [[CGPoint]], box: CGRect) -> [Int] {
        let parts = Set(groups(in: strokes).flatMap(\.strokes))
        return strokes.indices.filter { index in
            guard !parts.contains(index), let bounds = bounds(of: strokes[index]) else { return false }
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
