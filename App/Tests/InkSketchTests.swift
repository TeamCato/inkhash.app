import PencilKit
import XCTest
@testable import Inkhash

final class InkSketchTests: XCTestCase {
    private let tool = InkStrokeTool(pen: .pen, erasing: false, pixelErase: false, colorHex: "#2F6FED", width: 3)

    func testADragBecomesAStrokeInPagePoints() throws {
        let stroke = try XCTUnwrap(InkSketch.stroke(through: [CGPoint(x: 100, y: 200), CGPoint(x: 160, y: 240)], tool: tool, duration: 0.3))
        XCTAssertEqual(stroke.ink.inkType, .pen)
        XCTAssertEqual(stroke.path.count, 2)
        XCTAssertEqual(stroke.renderBounds.midX, 130, accuracy: 4)
        XCTAssertEqual(stroke.renderBounds.midY, 220, accuracy: 4)
        XCTAssertNil(InkSketch.stroke(through: [], tool: tool))
        XCTAssertEqual(InkSketch.stroke(through: [CGPoint(x: 5, y: 5)], tool: tool)?.path.count, 2, "a click leaves a dot")
    }

    func testTheEraserTakesWholeStrokesItTouches() throws {
        let near = try XCTUnwrap(InkSketch.stroke(through: [CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100)], tool: tool))
        let far = try XCTUnwrap(InkSketch.stroke(through: [CGPoint(x: 0, y: 400), CGPoint(x: 200, y: 400)], tool: tool))
        let drawing = PKDrawing(strokes: [near, far])

        let erased = try XCTUnwrap(InkSketch.erasing(at: CGPoint(x: 100, y: 104), radius: 4, from: drawing))
        XCTAssertEqual(erased.strokes.count, 1)
        XCTAssertEqual(erased.strokes.first?.renderBounds.midY ?? 0, 400, accuracy: 4)
        XCTAssertNil(InkSketch.erasing(at: CGPoint(x: 100, y: 250), radius: 4, from: drawing), "nothing hit, nothing changes")
    }
}
