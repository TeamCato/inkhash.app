import CoreGraphics
import Foundation

/// What the tools do to the elements of a page, as pure functions: the canvas only gathers
/// touches and shows the result. Page coordinates, y down. See ADR 0028.
public enum PageEdits {
    /// The `z` that puts a new element on top.
    public static func topZ(_ elements: [PageElement]) -> Int {
        (elements.map(\.z).max() ?? 0) + 1
    }

    /// The `z` that puts an element below all others.
    public static func bottomZ(_ elements: [PageElement]) -> Int {
        (elements.map(\.z).min() ?? 0) - 1
    }

    public static func removing(_ ids: Set<UUID>, from elements: [PageElement]) -> [PageElement] {
        elements.filter { !ids.contains($0.id) }
    }

    /// Moves the chosen elements to the front or the back.
    public static func restacking(_ ids: Set<UUID>, in elements: [PageElement], front: Bool) -> [PageElement] {
        let target = front ? topZ(elements) : bottomZ(elements)
        return elements.map { ids.contains($0.id) ? with($0) { $0.z = target } : $0 }
    }

    /// Sets or removes a link on the chosen elements. Ink cannot carry a link, so for chosen
    /// strokes (`strokeBounds`) an invisible link area goes over them. An area that only existed
    /// for its link goes with it. Returns the elements and what is chosen afterwards.
    public static func linking(
        _ ids: Set<UUID>, in elements: [PageElement], to target: String?, strokeBounds: CGRect?
    ) -> (elements: [PageElement], selected: Set<UUID>) {
        if let target, let strokes = strokeBounds, !strokes.isNull {
            let area = strokes.insetBy(dx: -12, dy: -12)
            let link = PageElement(kind: .link, x: area.midX, y: area.midY, width: area.width, height: area.height, z: topZ(elements), link: target)
            return (elements + [link], [link.id])
        }
        guard let target else {
            let kept = elements.filter { !(ids.contains($0.id) && $0.kind == .link) }
            return (kept.map { ids.contains($0.id) ? with($0) { $0.link = nil } : $0 }, ids.filter { id in kept.contains { $0.id == id } })
        }
        return (elements.map { ids.contains($0.id) ? with($0) { $0.link = target } : $0 }, ids)
    }

    /// An element moved and scaled by `transform`: its centre follows, its size scales, its
    /// rotation stays. Never smaller than 8 points.
    public static func transformed(_ element: PageElement, by transform: CGAffineTransform) -> PageElement {
        var copy = element
        let center = CGPoint(x: element.x, y: element.y).applying(transform)
        let factor = scale(of: transform)
        copy.x = center.x
        copy.y = center.y
        copy.width = max(8, element.width * factor)
        copy.height = max(8, element.height * factor)
        return copy
    }

    public static func transforming(_ ids: Set<UUID>, in elements: [PageElement], by transform: CGAffineTransform) -> [PageElement] {
        elements.map { ids.contains($0.id) ? transformed($0, by: transform) : $0 }
    }

    /// Scaling around `anchor` by how far the finger moved from it, between a tenth and tenfold.
    public static func resizeTransform(anchor: CGPoint, start: CGPoint, point: CGPoint) -> CGAffineTransform {
        let from = max(hypot(start.x - anchor.x, start.y - anchor.y), 1)
        let to = hypot(point.x - anchor.x, point.y - anchor.y)
        let factor = min(max(to / from, 0.1), 10)
        return CGAffineTransform(translationX: anchor.x, y: anchor.y).scaledBy(x: factor, y: factor).translatedBy(x: -anchor.x, y: -anchor.y)
    }

    /// The uniform scale in a transform made of moves and uniform scaling.
    public static func scale(of transform: CGAffineTransform) -> CGFloat {
        sqrt(abs(transform.a * transform.d - transform.b * transform.c))
    }

    /// Elements by their centre, strokes by the centre of their bounds, inside `rect`.
    public static func selection(in rect: CGRect, elements: [PageElement], strokeBounds: [CGRect]) -> (ids: Set<UUID>, strokes: [Int]) {
        let ids = Set(elements.filter { rect.contains(CGPoint(x: $0.x, y: $0.y)) }.map(\.id))
        let strokes = strokeBounds.enumerated().filter { rect.contains(CGPoint(x: $0.element.midX, y: $0.element.midY)) }.map(\.offset)
        return (ids, strokes)
    }

    /// Where a new photo goes: centred in view, at most 480 points or the page width less a margin
    /// on its long side, at least 40, slightly turned.
    public static func image(
        blob: String, pixelSize: CGSize, center: CGPoint, pageWidth: Double, z: Int, rotation: Double
    ) -> PageElement {
        let longest = min(480, pageWidth - 80)
        let ratio = longest / max(pixelSize.width, pixelSize.height, 1)
        return PageElement(
            kind: .image, x: center.x, y: center.y,
            width: max(40, pixelSize.width * ratio), height: max(40, pixelSize.height * ratio),
            rotation: rotation, z: z, blob: blob, frame: .classic
        )
    }

    /// A strip of tape along a drag. A short touch puts down one of the usual length, slightly askew.
    public static func tape(from start: CGPoint, to end: CGPoint, width: Double, color: String?, z: Int) -> PageElement {
        var length = hypot(end.x - start.x, end.y - start.y)
        var angle = atan2(end.y - start.y, end.x - start.x)
        var center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        if length < 20 {
            length = 240
            angle = 0.08
            center = start
        }
        return PageElement(kind: .tape, x: center.x, y: center.y, width: length, height: width, rotation: angle, z: z, color: color)
    }

    /// Where a shape dragged from `start` to `end` lies: a line is a flat box along the drag,
    /// turned, at least `lineThickness` thick so it can be hit; other forms fill the dragged
    /// rectangle. Nil for a drag too short to mean anything.
    public static func shapeBox(
        _ form: PageElement.ShapeForm, from start: CGPoint, to end: CGPoint, lineThickness: Double
    ) -> (x: Double, y: Double, width: Double, height: Double, rotation: Double)? {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 4 else { return nil }
        if form == .line {
            return ((start.x + end.x) / 2, (start.y + end.y) / 2, length, max(lineThickness, 24), atan2(end.y - start.y, end.x - start.x))
        }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        guard rect.width > 4, rect.height > 4 else { return nil }
        return (rect.midX, rect.midY, rect.width, rect.height, 0)
    }

    /// A drawn outline as a freehand mask: 0…1 in the photo area of the image, at most 400 points.
    public static func mask(from points: [CGPoint], on element: PageElement) -> PageElement.Mask? {
        guard points.count > 2 else { return nil }
        let content = ElementGeometry.contentRect(in: CGRect(x: 0, y: 0, width: element.width, height: element.height), frame: element.frame)
        let inverse = ElementGeometry.transform(of: element).inverted()
        let normalized = points.map { point -> PageElement.Point in
            let local = point.applying(inverse)
            return PageElement.Point(
                x: min(max((local.x - content.minX) / max(content.width, 1), 0), 1),
                y: min(max((local.y - content.minY) / max(content.height, 1), 0), 1)
            )
        }
        return PageElement.Mask(kind: .freehand, points: thinned(normalized))
    }

    /// At most 400 points, so the outline stays within what the server takes.
    public static func thinned(_ points: [PageElement.Point]) -> [PageElement.Point] {
        guard points.count > 400 else { return points }
        let step = Double(points.count) / 400
        return (0..<400).map { points[Int(Double($0) * step)] }
    }

    /// The page height a drawing needs: if what is drawn or placed reaches into the margin at the
    /// bottom, the page grows by a step, up to the limit. See ADR 0042.
    public static func grownHeight(current: Double, contentBottom: Double, margin: Double, step: Double, limit: Double) -> Double {
        guard contentBottom > 0, contentBottom > current - margin else { return current }
        return min(limit, contentBottom + step)
    }

    private static func with(_ element: PageElement, _ change: (inout PageElement) -> Void) -> PageElement {
        var copy = element
        change(&copy)
        return copy
    }
}
