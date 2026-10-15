import CoreGraphics
import Foundation

/// The largest area a few strokes close in, found on a grid of one page point per cell. Ink is
/// drawn wide, so small gaps where strokes meet still close, and ends that overshoot a corner
/// stay outside. See ADR 0065.
struct EnclosedArea: Equatable {
    /// The area out to the middle of the ink around it, in page coordinates.
    var rect: CGRect
    /// Share of `rect`'s cells, measured inside the ink, that the area fills: 1 for a box, about 0.8 for a circle.
    var fill: Double
    /// Size of the area in square points.
    var size: Double

    /// Nil if the strokes close in nothing, or are too large to look at.
    static func largest(in parts: [[CGPoint]], inkRadius: CGFloat, maxSide: Int = 120) -> EnclosedArea? {
        let points = parts.flatMap { $0 }
        guard let first = points.first else { return nil }
        let margin: CGFloat = 3 + inkRadius
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        let originX = minX - margin, originY = minY - margin
        let width = Int((maxX - originX + margin).rounded(.up))
        let height = Int((maxY - originY + margin).rounded(.up))
        guard width <= maxSide, height <= maxSide else { return nil }

        var ink = [Bool](repeating: false, count: width * height)
        let reach = Int(inkRadius.rounded(.up)) + 1
        func stamp(_ point: CGPoint) {
            let px = point.x - originX, py = point.y - originY
            for y in max(0, Int(py) - reach)...min(height - 1, Int(py) + reach) {
                for x in max(0, Int(px) - reach)...min(width - 1, Int(px) + reach) {
                    let dx = CGFloat(x) + 0.5 - px, dy = CGFloat(y) + 0.5 - py
                    if dx * dx + dy * dy <= inkRadius * inkRadius { ink[y * width + x] = true }
                }
            }
        }
        for part in parts {
            guard let start = part.first else { continue }
            stamp(start)
            for (a, b) in zip(part, part.dropFirst()) {
                let steps = max(1, Int((hypot(b.x - a.x, b.y - a.y) / 0.5).rounded(.up)))
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    stamp(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
        }

        var seen = ink
        func flood(_ start: Int) -> [Int] {
            var cells = [start]
            var next = 0
            seen[start] = true
            while next < cells.count {
                let cell = cells[next]
                next += 1
                let x = cell % width, y = cell / width
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                where nx >= 0 && nx < width && ny >= 0 && ny < height && !seen[ny * width + nx] {
                    seen[ny * width + nx] = true
                    cells.append(ny * width + nx)
                }
            }
            return cells
        }
        _ = flood(0)
        var best: [Int] = []
        for cell in seen.indices where !seen[cell] {
            let area = flood(cell)
            if area.count > best.count { best = area }
        }
        guard !best.isEmpty else { return nil }

        var lowX = width, lowY = height, highX = 0, highY = 0
        for cell in best {
            lowX = min(lowX, cell % width); highX = max(highX, cell % width)
            lowY = min(lowY, cell / width); highY = max(highY, cell / width)
        }
        let inner = (highX - lowX + 1) * (highY - lowY + 1)
        let rect = CGRect(
            x: originX + CGFloat(lowX) - inkRadius, y: originY + CGFloat(lowY) - inkRadius,
            width: CGFloat(highX - lowX + 1) + 2 * inkRadius, height: CGFloat(highY - lowY + 1) + 2 * inkRadius
        )
        return EnclosedArea(rect: rect, fill: Double(best.count) / Double(inner), size: Double(best.count))
    }
}
