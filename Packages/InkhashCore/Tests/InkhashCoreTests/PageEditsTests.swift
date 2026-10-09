import CoreGraphics
import XCTest
@testable import InkhashCore

final class PageEditsTests: XCTestCase {
    private func box(_ kind: PageElement.Kind = .shape, x: Double = 100, y: Double = 100, width: Double = 40, height: Double = 20, z: Int = 0, link: String? = nil) -> PageElement {
        PageElement(kind: kind, x: x, y: y, width: width, height: height, z: z, shape: kind == .shape ? .rect : nil, link: link)
    }

    func testStackingGoesAboveOrBelowAll() {
        let a = box(z: 2)
        let b = box(z: -1)
        XCTAssertEqual(PageEdits.topZ([a, b]), 3)
        XCTAssertEqual(PageEdits.bottomZ([a, b]), -2)
        XCTAssertEqual(PageEdits.topZ([]), 1)
        let front = PageEdits.restacking([b.id], in: [a, b], front: true)
        XCTAssertEqual(front.first { $0.id == b.id }?.z, 3)
        let back = PageEdits.restacking([a.id], in: [a, b], front: false)
        XCTAssertEqual(back.first { $0.id == a.id }?.z, -2)
        XCTAssertEqual(PageEdits.removing([a.id], from: [a, b]).map(\.id), [b.id])
    }

    func testLinkingElementsSetsAndClearsTheirLink() {
        let shape = box()
        let area = box(.link, link: "https://a.example")
        let set = PageEdits.linking([shape.id], in: [shape, area], to: "inkhash://note/x", strokeBounds: nil)
        XCTAssertEqual(set.elements.first { $0.id == shape.id }?.link, "inkhash://note/x")
        XCTAssertEqual(set.selected, [shape.id])
        // Clearing drops a bare link area entirely and only the link from the others.
        let cleared = PageEdits.linking([shape.id, area.id], in: set.elements, to: nil, strokeBounds: nil)
        XCTAssertEqual(cleared.elements.map(\.id), [shape.id])
        XCTAssertNil(cleared.elements[0].link)
        XCTAssertEqual(cleared.selected, [shape.id])
    }

    func testLinkingInkPutsAnAreaOverIt() {
        let result = PageEdits.linking([], in: [box(z: 4)], to: "https://a.example", strokeBounds: CGRect(x: 10, y: 20, width: 100, height: 50))
        XCTAssertEqual(result.elements.count, 2)
        let area = result.elements[1]
        XCTAssertEqual(area.kind, .link)
        XCTAssertEqual(area.link, "https://a.example")
        XCTAssertEqual(area.width, 124)
        XCTAssertEqual(area.height, 74)
        XCTAssertEqual(area.x, 60)
        XCTAssertEqual(area.y, 45)
        XCTAssertEqual(area.z, 5)
        XCTAssertEqual(result.selected, [area.id])
    }

    func testMovingAndScalingKeepsRotationAndAMinimumSize() {
        var element = box(x: 10, y: 10, width: 40, height: 20)
        element.rotation = 0.3
        let moved = PageEdits.transformed(element, by: CGAffineTransform(translationX: 5, y: -3))
        XCTAssertEqual(moved.x, 15)
        XCTAssertEqual(moved.y, 7)
        XCTAssertEqual(moved.width, 40)
        XCTAssertEqual(moved.rotation, 0.3)
        let shrunk = PageEdits.transformed(element, by: CGAffineTransform(scaleX: 0.1, y: 0.1))
        XCTAssertEqual(shrunk.width, 8)
        XCTAssertEqual(shrunk.height, 8)
        let other = box()
        let both = PageEdits.transforming([element.id], in: [element, other], by: CGAffineTransform(translationX: 1, y: 1))
        XCTAssertEqual(both[1], other)
    }

    func testResizeScalesAroundTheAnchorWithinLimits() {
        let anchor = CGPoint(x: 0, y: 0)
        let double = PageEdits.resizeTransform(anchor: anchor, start: CGPoint(x: 10, y: 0), point: CGPoint(x: 20, y: 0))
        XCTAssertEqual(PageEdits.scale(of: double), 2, accuracy: 0.0001)
        XCTAssertEqual(anchor.applying(double), anchor)
        let huge = PageEdits.resizeTransform(anchor: anchor, start: CGPoint(x: 1, y: 0), point: CGPoint(x: 1000, y: 0))
        XCTAssertEqual(PageEdits.scale(of: huge), 10, accuracy: 0.0001)
        let tiny = PageEdits.resizeTransform(anchor: anchor, start: CGPoint(x: 100, y: 0), point: CGPoint(x: 1, y: 0))
        XCTAssertEqual(PageEdits.scale(of: tiny), 0.1, accuracy: 0.0001)
    }

    func testSelectionGoesByCentres() {
        let inside = box(x: 50, y: 50)
        let outside = box(x: 500, y: 50)
        let result = PageEdits.selection(
            in: CGRect(x: 0, y: 0, width: 100, height: 100),
            elements: [inside, outside],
            strokeBounds: [CGRect(x: 10, y: 10, width: 20, height: 20), CGRect(x: 90, y: 90, width: 100, height: 100)]
        )
        XCTAssertEqual(result.ids, [inside.id])
        XCTAssertEqual(result.strokes, [0])
    }

    func testImagesFitTheirLongSideAndStayVisible() {
        let wide = PageEdits.image(blob: "b", pixelSize: CGSize(width: 4000, height: 2000), center: CGPoint(x: 300, y: 400), pageWidth: 768, z: 3, rotation: 0.01)
        XCTAssertEqual(wide.width, 480)
        XCTAssertEqual(wide.height, 240)
        XCTAssertEqual(wide.kind, .image)
        XCTAssertEqual(wide.blob, "b")
        XCTAssertEqual(wide.frame, .classic)
        XCTAssertEqual(wide.z, 3)
        let narrowPage = PageEdits.image(blob: "b", pixelSize: CGSize(width: 1000, height: 10), center: .zero, pageWidth: 300, z: 0, rotation: 0)
        XCTAssertEqual(narrowPage.width, 220)
        XCTAssertEqual(narrowPage.height, 40, "never thinner than 40")
    }

    func testTapeFollowsTheDragOrLiesDownAtAShortTouch() {
        let strip = PageEdits.tape(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), width: 30, color: "#F0E6C7", z: 1)
        XCTAssertEqual(strip.width, 100)
        XCTAssertEqual(strip.height, 30)
        XCTAssertEqual(strip.x, 50)
        XCTAssertEqual(strip.rotation, 0)
        XCTAssertEqual(strip.color, "#F0E6C7")
        let touch = PageEdits.tape(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 11), width: 30, color: nil, z: 1)
        XCTAssertEqual(touch.width, 240)
        XCTAssertEqual(touch.rotation, 0.08)
        XCTAssertEqual(touch.x, 10)
    }

    func testShapeBoxes() throws {
        let line = try XCTUnwrap(PageEdits.shapeBox(.line, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 100), lineThickness: 4))
        XCTAssertEqual(line.width, 100)
        XCTAssertEqual(line.height, 24, "a thin line still gets a box to hit")
        XCTAssertEqual(line.rotation, .pi / 2, accuracy: 0.0001)
        let rect = try XCTUnwrap(PageEdits.shapeBox(.rect, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 10, y: 20), lineThickness: 4))
        XCTAssertEqual(rect.x, 30)
        XCTAssertEqual(rect.y, 35)
        XCTAssertEqual(rect.width, 40)
        XCTAssertEqual(rect.height, 30)
        XCTAssertNil(PageEdits.shapeBox(.rect, from: .zero, to: CGPoint(x: 2, y: 2), lineThickness: 4))
        XCTAssertNil(PageEdits.shapeBox(.ellipse, from: .zero, to: CGPoint(x: 100, y: 2), lineThickness: 4), "too flat to be a shape")
    }

    func testMaskIsNormalizedToThePhotoArea() throws {
        let image = PageElement(kind: .image, x: 100, y: 100, width: 200, height: 100, blob: "b")
        let mask = try XCTUnwrap(PageEdits.mask(from: [CGPoint(x: 0, y: 50), CGPoint(x: 200, y: 50), CGPoint(x: 100, y: 150), CGPoint(x: 400, y: 400)], on: image))
        XCTAssertEqual(mask.kind, .freehand)
        XCTAssertEqual(mask.points, [.init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 0.5, y: 1), .init(x: 1, y: 1)])
        XCTAssertNil(PageEdits.mask(from: [.zero, .zero], on: image))
    }

    func testLongOutlinesAreThinned() {
        let points = (0..<1000).map { PageElement.Point(x: Double($0) / 1000, y: 0) }
        let thinned = PageEdits.thinned(points)
        XCTAssertEqual(thinned.count, 400)
        XCTAssertEqual(thinned.first, points.first)
        XCTAssertEqual(PageEdits.thinned(Array(points.prefix(10))).count, 10)
    }

    func testPagesGrowWhenWritingReachesTheMargin() {
        XCTAssertEqual(PageEdits.grownHeight(current: 1024, contentBottom: 500, margin: 320, step: 640, limit: 10_000), 1024)
        XCTAssertEqual(PageEdits.grownHeight(current: 1024, contentBottom: 800, margin: 320, step: 640, limit: 10_000), 1440)
        XCTAssertEqual(PageEdits.grownHeight(current: 9800, contentBottom: 9700, margin: 320, step: 640, limit: 10_000), 10_000)
        XCTAssertEqual(PageEdits.grownHeight(current: 1024, contentBottom: 0, margin: 320, step: 640, limit: 10_000), 1024)
    }

    func testGeometryFindsTheTopmostVisibleElementFirst() {
        let low = box(x: 100, y: 100, z: 0)
        let high = box(x: 100, y: 100, z: 5)
        let area = box(.link, x: 100, y: 100, z: 9, link: "https://a.example")
        XCTAssertEqual(ElementGeometry.element(at: CGPoint(x: 100, y: 100), in: [low, high, area])?.id, high.id)
        XCTAssertEqual(ElementGeometry.element(at: CGPoint(x: 100, y: 100), in: [area])?.id, area.id)
        XCTAssertNil(ElementGeometry.element(at: CGPoint(x: 900, y: 900), in: [low]))
        XCTAssertEqual(ElementGeometry.bounds(of: low), CGRect(x: 80, y: 90, width: 40, height: 20))
        XCTAssertEqual(ElementGeometry.badgePoint(of: low), CGPoint(x: 120, y: 90))
    }

    func testFramesLeaveRoomAroundThePhoto() {
        let box = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(ElementGeometry.contentRect(in: box, frame: nil), box)
        XCTAssertEqual(ElementGeometry.contentRect(in: box, frame: .init(style: .solid, width: 12)), box.insetBy(dx: 12, dy: 12))
        XCTAssertEqual(ElementGeometry.contentRect(in: box, frame: .init(style: .polaroid, width: 12)), CGRect(x: 12, y: 12, width: 176, height: 52))
    }
}
