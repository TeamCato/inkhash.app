import InkhashCore
import PencilKit
import XCTest
@testable import Inkhash

/// The due day at a task in the text editor. See ADR 0060.
@MainActor
final class TaskDueEditingTests: EditorTestCase {
    func testTheChipSetsChangesAndRemovesTheDay() {
        open("- [ ] Angebot\n")
        view.selectedRange = NSRange(location: 3, length: 0)
        engine.selectionChanged()
        engine.setDue("2026-10-20")
        XCTAssertEqual(markdown, "- [ ] Angebot 📅 2026-10-20\n")
        XCTAssertEqual(view.selectedRange.location, 3, "the cursor stays where it was")
        engine.setDue("2026-10-21")
        XCTAssertEqual(markdown, "- [ ] Angebot 📅 2026-10-21\n")
        engine.setDue(nil)
        XCTAssertEqual(markdown, "- [ ] Angebot\n")
    }

    func testOnlyTasksGetADay() {
        open("Angebot\n")
        view.selectedRange = NSRange(location: 3, length: 0)
        engine.selectionChanged()
        engine.setDue("2026-10-20")
        XCTAssertEqual(markdown, "Angebot\n")
    }

    func testSettingTheDayCanBeUndone() {
        open("- [ ] Angebot\n")
        view.selectedRange = NSRange(location: 3, length: 0)
        engine.selectionChanged()
        engine.setDue("2026-10-20")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        view.undoManager?.undo()
        XCTAssertEqual(markdown, "- [ ] Angebot\n")
    }
}

/// Ticking a handwritten task from the list draws into its box. See ADR 0060.
@MainActor
final class InkTaskTickTests: LibraryTestCase {
    private func stroke(_ points: [CGPoint]) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: 0.01 * Double(index), size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
    }

    private func square(_ rect: CGRect) -> [CGPoint] {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY + 1),
        ]
        return zip(corners, corners.dropFirst()).flatMap { from, to in
            (0..<10).map { step in
                let t = CGFloat(step) / 10
                return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            }
        }
    }

    func testTickingDrawsATickAndOpeningTakesItAway() throws {
        let box = CGRect(x: 40, y: 100, width: 22, height: 22)
        let drawing = PKDrawing(strokes: [stroke(square(box))])
        var note = try XCTUnwrap(library.newInkNote(drawing: drawing.dataRepresentation()))
        let task = InkTask(x: box.minX, y: box.minY, width: box.width, height: box.height, text: "Milch")
        note.pages?[0].tasks = [task]
        library.add(note)
        let item = try XCTUnwrap(TaskList.items(of: note).first)

        library.setTask(item, checked: true)
        var stored = try XCTUnwrap(library.record(note.id)?.note)
        XCTAssertEqual(stored.pages?[0].tasks.first?.checked, true)
        var strokes = try PKDrawing(data: XCTUnwrap(library.drawingData(for: stored.pages![0].blob))).strokes
        XCTAssertEqual(strokes.count, 2)
        XCTAssertEqual(TaskBoxes.marks(in: strokes.map(InkTasks.points(of:))).ticked, [true])

        library.setTask(item, checked: false)
        stored = try XCTUnwrap(library.record(note.id)?.note)
        XCTAssertEqual(stored.pages?[0].tasks.first?.checked, false)
        strokes = try PKDrawing(data: XCTUnwrap(library.drawingData(for: stored.pages![0].blob))).strokes
        XCTAssertEqual(strokes.count, 1, "the box stays")
    }

    /// A highlight over the box is no tick, as the recognizer sees it. Reviewer finding.
    func testAMarkerOverTheBoxIsNoTick() throws {
        let box = CGRect(x: 40, y: 100, width: 22, height: 22)
        let marker = PKStroke(
            ink: PKInk(.marker, color: .yellow),
            path: PKStrokePath(controlPoints: [CGPoint(x: 30, y: 111), CGPoint(x: 200, y: 111)].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index), size: CGSize(width: 20, height: 20), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date())
        )
        let drawing = PKDrawing(strokes: [stroke(square(box)), marker])
        var note = try XCTUnwrap(library.newInkNote(drawing: drawing.dataRepresentation()))
        note.pages?[0].tasks = [InkTask(x: box.minX, y: box.minY, width: box.width, height: box.height, text: "Milch")]
        library.add(note)
        let item = try XCTUnwrap(TaskList.items(of: note).first)
        library.setTask(item, checked: true)
        let stored = try XCTUnwrap(library.record(note.id)?.note)
        let strokes = try PKDrawing(data: XCTUnwrap(library.drawingData(for: stored.pages![0].blob))).strokes
        XCTAssertEqual(strokes.count, 3, "the tick is drawn despite the highlight")
        library.setTask(item, checked: false)
        let reopened = try XCTUnwrap(library.record(note.id)?.note)
        let after = try PKDrawing(data: XCTUnwrap(library.drawingData(for: reopened.pages![0].blob))).strokes
        XCTAssertEqual(after.count, 2, "only the tick goes, the highlight stays")
        XCTAssertTrue(after.contains { $0.ink.inkType == .marker })
    }

    func testTheDayOfAHandwrittenTaskStaysAtTheTask() throws {
        var note = try XCTUnwrap(library.newInkNote(drawing: PKDrawing().dataRepresentation()))
        note.pages?[0].tasks = [InkTask(x: 40, y: 100, width: 22, height: 22, text: "Milch")]
        library.add(note)
        let item = try XCTUnwrap(TaskList.items(of: note).first)
        library.setTask(item, due: "2026-10-20")
        XCTAssertEqual(library.record(note.id)?.note.pages?[0].tasks.first?.due, "2026-10-20")
    }
}
