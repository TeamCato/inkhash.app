import InkhashCore
import PencilKit
import XCTest
@testable import Inkhash

/// The page canvas without SwiftUI around it: a coordinator on a real `PKCanvasView`.
@MainActor
final class InkPageCanvasTests: XCTestCase {
    private var drawings: [(UUID, Data, Double)] = []
    private var elementChanges: [(UUID, [PageElement])] = []
    private var coordinator: InkPageCanvas.Coordinator!
    private var canvas: PKCanvasView!
    private let page = UUID()

    override func setUp() async throws {
        drawings = []
        elementChanges = []
        let parent = InkPageCanvas(
            drawingData: PKDrawing().dataRepresentation(), elements: [], pageID: page,
            pageWidth: PageGeometry.width, pageHeight: PageGeometry.height, paper: .standard, scale: 1,
            fingerDrawing: true, tools: InkToolState(), editor: InkEditorState(), loadBlob: { _ in nil },
            onDrawing: { [weak self] id, data, height in self?.drawings.append((id, data, height)) },
            onElements: { [weak self] id, elements in self?.elementChanges.append((id, elements)) }
        )
        coordinator = InkPageCanvas.Coordinator(parent: parent)
        canvas = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 768, height: 1024))
        coordinator.canvas = canvas
        coordinator.pageID = page
        coordinator.install(in: canvas)
        coordinator.syncElements([], force: true)
    }

    private func stroke(at y: CGFloat) -> PKStroke {
        let points = [CGPoint(x: 100, y: y), CGPoint(x: 200, y: y + 10)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    /// P-034: what is still waiting to be saved goes to the page it was drawn on.
    func testAWaitingDrawingIsSavedForItsPage() {
        canvas.drawing = PKDrawing(strokes: [stroke(at: 100)])
        coordinator.canvasViewDrawingDidChange(canvas)
        XCTAssertTrue(drawings.isEmpty, "saving waits for a pause")
        coordinator.flush()
        XCTAssertEqual(drawings.count, 1)
        XCTAssertEqual(drawings.first?.0, page)
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(drawings.first?.1)).strokes.count, 1)
        coordinator.flush()
        XCTAssertEqual(drawings.count, 1, "nothing twice")
    }

    func testWritingNearTheBottomGrowsThePage() {
        canvas.drawing = PKDrawing(strokes: [stroke(at: 900)])
        coordinator.publish(canvas.drawing.dataRepresentation())
        XCTAssertGreaterThan(drawings.last?.2 ?? 0, PageGeometry.height)
    }

    func testImagesLandOnThePageAndCanBeDeleted() {
        coordinator.insertImage(blob: String(repeating: "a", count: 64), pixelSize: CGSize(width: 2000, height: 1000))
        let placed = try? XCTUnwrap(elementChanges.last?.1)
        XCTAssertEqual(placed?.count, 1)
        XCTAssertEqual(placed?.first?.kind, .image)
        XCTAssertEqual(placed?.first?.width, 480)
        XCTAssertEqual(elementChanges.last?.0, page)
        coordinator.deleteSelection()
        XCTAssertEqual(elementChanges.last?.1, [])
    }

    func testLinkingTheSelectionAndStackingIt() throws {
        coordinator.insertImage(blob: "b", pixelSize: CGSize(width: 100, height: 100))
        coordinator.insertImage(blob: "c", pixelSize: CGSize(width: 100, height: 100))
        let second = try XCTUnwrap(elementChanges.last?.1.last)
        coordinator.setLink("https://inkhash.app")
        XCTAssertEqual(elementChanges.last?.1.first { $0.id == second.id }?.link, "https://inkhash.app")
        coordinator.restack(front: false)
        let stacked = try XCTUnwrap(elementChanges.last?.1)
        let moved = try XCTUnwrap(stacked.first { $0.id == second.id })
        XCTAssertTrue(stacked.allSatisfy { $0.id == second.id || $0.z > moved.z })
    }
}
