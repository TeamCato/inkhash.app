import CoreGraphics
import Foundation
import InkhashCore
import PencilKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Drawn boxes on a page as PencilKit sees them: the strokes as points for `TaskBoxes`, and the
/// tick the task list draws or takes away. The ink stays the truth. See ADR 0060.
enum InkTasks {
    /// The points of a stroke in page coordinates.
    static func points(of stroke: PKStroke) -> [CGPoint] {
        stroke.path.interpolatedPoints(by: .distance(2)).map { $0.location.applying(stroke.transform) }
    }

    /// The drawing with a tick drawn into `box`, or without the strokes on it. Nil if nothing changes.
    /// Marker strokes are highlights, never ticks: the recognizer leaves them out too.
    static func drawing(_ drawing: PKDrawing, ticking box: CGRect, checked: Bool) -> PKDrawing? {
        let pens = drawing.strokes.enumerated().filter { $0.element.ink.inkType != .marker }
        let ticks = TaskBoxes.ticks(in: pens.map { points(of: $0.element) }, box: box).map { pens[$0].offset }
        if checked {
            guard ticks.isEmpty else { return nil }
            return PKDrawing(strokes: drawing.strokes + [tick(in: box)])
        }
        guard !ticks.isEmpty else { return nil }
        let removed = Set(ticks)
        return PKDrawing(strokes: drawing.strokes.enumerated().filter { !removed.contains($0.offset) }.map(\.element))
    }

    private static func tick(in box: CGRect) -> PKStroke {
        let width = max(2, box.width * 0.12)
        let controlPoints = TaskBoxes.tick(in: box).enumerated().map { index, point in
            PKStrokePoint(
                location: point, timeOffset: 0.01 * Double(index), size: CGSize(width: width, height: width),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let ink = PKInk(.pen, color: PlatformColor(inkHex: "#1C1D20"))
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
    }
}
