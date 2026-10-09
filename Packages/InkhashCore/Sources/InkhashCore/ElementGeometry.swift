import CoreGraphics
import Foundation

/// Geometry of elements in page coordinates, y down. See ADR 0028.
public enum ElementGeometry {
    /// Maps a point in the element's unrotated box (origin top-left) to the page.
    public static func transform(of element: PageElement) -> CGAffineTransform {
        CGAffineTransform(translationX: element.x, y: element.y)
            .rotated(by: element.rotation)
            .translatedBy(x: -element.width / 2, y: -element.height / 2)
    }

    public static func contains(_ element: PageElement, _ point: CGPoint, slop: CGFloat = 0) -> Bool {
        let local = point.applying(transform(of: element).inverted())
        return CGRect(x: 0, y: 0, width: element.width, height: element.height).insetBy(dx: -slop, dy: -slop).contains(local)
    }

    /// The axis-aligned box around the rotated element.
    public static func bounds(of element: PageElement) -> CGRect {
        CGRect(x: 0, y: 0, width: element.width, height: element.height).applying(transform(of: element))
    }

    /// Where the link badge sits: the top-right corner of the box, in page coordinates.
    public static func badgePoint(of element: PageElement) -> CGPoint {
        let bounds = bounds(of: element)
        return CGPoint(x: bounds.maxX, y: bounds.minY)
    }

    /// Topmost element under the point, link areas last since they are invisible.
    public static func element(at point: CGPoint, in elements: [PageElement], slop: CGFloat = 6) -> PageElement? {
        elements.sorted { $0.z > $1.z }.first { $0.kind != .link && contains($0, point, slop: slop) }
            ?? elements.sorted { $0.z > $1.z }.first { $0.kind == .link && contains($0, point) }
    }

    /// The part of an image's box the photo fills, inside its frame.
    public static func contentRect(in box: CGRect, frame: PageElement.Frame?) -> CGRect {
        guard let frame else { return box }
        switch frame.style {
        case .none:
            return box
        case .solid:
            let inset = min(CGFloat(frame.width), min(box.width, box.height) / 4)
            return box.insetBy(dx: inset, dy: inset)
        case .polaroid:
            let inset = min(CGFloat(frame.width), min(box.width, box.height) / 6)
            return CGRect(x: box.minX + inset, y: box.minY + inset, width: box.width - inset * 2, height: box.height - inset * 4)
        }
    }
}
