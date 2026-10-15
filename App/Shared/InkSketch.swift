import Foundation
import PencilKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Strokes made without PencilKit's canvas: from mouse drags on the Mac. All in page points, so
/// they land in the same drawing the iPad writes and render the same everywhere. See ADR 0058.
enum InkSketch {
    /// A stroke through `points`, in the tool's pen, colour and width. Nil for no points.
    static func stroke(through points: [CGPoint], tool: InkStrokeTool, duration: TimeInterval = 0) -> PKStroke? {
        guard let first = points.first else { return nil }
        // A click without movement still leaves a dot.
        let path = points.count == 1 ? [first, CGPoint(x: first.x + 0.1, y: first.y)] : points
        let step = path.count > 1 ? duration / Double(path.count - 1) : 0
        let size = CGSize(width: tool.width, height: tool.width)
        let controlPoints = path.enumerated().map { index, point in
            PKStrokePoint(
                location: point, timeOffset: step * Double(index), size: size,
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let ink = PKInk(tool.pen.inkType, color: PlatformColor(inkHex: tool.colorHex))
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
    }

    /// The drawing without every stroke that passes within `radius` of `point`, or nil if none does.
    /// Whole strokes go, like PencilKit's vector eraser.
    static func erasing(at point: CGPoint, radius: CGFloat, from drawing: PKDrawing) -> PKDrawing? {
        let kept = drawing.strokes.filter { !touches($0, point: point, radius: radius) }
        return kept.count == drawing.strokes.count ? nil : PKDrawing(strokes: kept)
    }

    static func touches(_ stroke: PKStroke, point: CGPoint, radius: CGFloat) -> Bool {
        guard stroke.renderBounds.insetBy(dx: -radius, dy: -radius).contains(point) else { return false }
        // Thin strokes are hard to hit with a mouse; a little room helps.
        let reach = radius + 2
        for sample in stroke.path.interpolatedPoints(by: .distance(2)) {
            let location = sample.location.applying(stroke.transform)
            let width = max(sample.size.width, sample.size.height) / 2
            if hypot(location.x - point.x, location.y - point.y) <= reach + width { return true }
        }
        return false
    }
}
