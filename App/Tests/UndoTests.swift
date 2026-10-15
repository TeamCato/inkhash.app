import UIKit
import XCTest
@testable import Inkhash

/// Undo and redo in the text view across edits of the engine. See ADR 0059 and P-060.
@MainActor
final class UndoTests: EditorTestCase {
    private var undo: UndoManager { view.undoManager! }

    /// Lets the run loop close the open undo group, as after a touch or key press.
    private func endEvent() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func testAShortcutCanBeUndoneAndRedone() {
        open("Plan\n")
        view.selectedRange = NSRange(location: 0, length: 0)
        engine.selectionChanged()
        type("#")
        endEvent()
        type(" ")
        endEvent()
        XCTAssertEqual(markdown, "# Plan\n")
        undo.undo()
        XCTAssertEqual(markdown, "#Plan\n")
        undo.undo()
        XCTAssertEqual(markdown, "Plan\n")
        undo.redo()
        undo.redo()
        XCTAssertEqual(markdown, "# Plan\n")
    }

    func testTypingBeforeAndAfterAnEngineEditStaysUndoable() {
        open("Text\n")
        view.selectedRange = NSRange(location: 4, length: 0)
        engine.selectionChanged()
        engine.setType(.heading2)
        endEvent()
        XCTAssertEqual(markdown, "## Text\n")
        type(" mehr")
        endEvent()
        XCTAssertEqual(markdown, "## Text mehr\n")
        undo.undo()
        XCTAssertEqual(markdown, "## Text\n")
        undo.undo()
        XCTAssertEqual(markdown, "Text\n")
        undo.redo()
        XCTAssertEqual(markdown, "## Text\n")
        undo.redo()
        XCTAssertEqual(markdown, "## Text mehr\n")
    }

    func testBoldIsUndoneWithItsSelection() {
        open("eins zwei\n")
        view.selectedRange = NSRange(location: 5, length: 4)
        engine.selectionChanged()
        engine.toggle(.toggleBold)
        endEvent()
        XCTAssertEqual(markdown, "eins **zwei**\n")
        undo.undo()
        XCTAssertEqual(markdown, "eins zwei\n")
        XCTAssertEqual(view.selectedRange, NSRange(location: 5, length: 4))
    }

    func testTypingIsOneStepPerRunAndAJumpStartsANewOne() {
        open()
        type("eins")
        endEvent()
        type(" zwei")
        endEvent()
        view.selectedRange = NSRange(location: 0, length: 0)
        engine.selectionChanged()
        type("x")
        endEvent()
        XCTAssertEqual(view.storage.string, "xeins zwei")
        undo.undo()
        XCTAssertEqual(view.storage.string, "eins zwei")
        undo.undo()
        XCTAssertEqual(view.storage.string, "")
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(view.storage.string, "eins zwei")
    }

    /// UIKit drops its own typing steps when the engine edits the text; the view keeps its own. P-060.
    func testTypingBeforeAnEngineEditSurvivesIt() {
        open()
        type("Text")
        endEvent()
        engine.setType(.heading1)
        endEvent()
        XCTAssertEqual(markdown, "# Text\n")
        undo.undo()
        XCTAssertEqual(markdown, "Text\n")
        undo.undo()
        XCTAssertEqual(view.storage.string, "")
    }

    func testHistoryFollowsTheButtons() {
        open("Text\n")
        let history = UndoHistory()
        history.follow(view.undoManager)
        XCTAssertFalse(history.canUndo)
        view.selectedRange = NSRange(location: 0, length: 0)
        engine.selectionChanged()
        engine.setType(.heading1)
        endEvent()
        XCTAssertTrue(history.canUndo)
        history.undo()
        XCTAssertEqual(markdown, "Text\n")
        XCTAssertTrue(history.canRedo)
        history.redo()
        XCTAssertEqual(markdown, "# Text\n")
        XCTAssertFalse(history.canRedo)
    }
}
