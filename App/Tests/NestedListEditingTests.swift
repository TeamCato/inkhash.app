import InkhashCore
import UIKit
import XCTest
@testable import Inkhash

/// Tab and Shift-Tab on list items with a hardware keyboard. See ADR 0086.
@MainActor
final class NestedListEditingTests: EditorTestCase {
    func testTabFromTheKeyboardIndents() {
        open("- eins\n- zwei\n")
        view.selectedRange = NSRange(location: (view.storage.string as NSString).range(of: "zwei").location, length: 0)
        type("\t")
        XCTAssertEqual(markdown, "- eins\n  - zwei\n")
        XCTAssertFalse(view.storage.string.contains("\t"))
    }

    func testReturnKeepsTheLevelAndLeavesItWhenEmpty() {
        open("- eins\n- zwei\n")
        view.selectedRange = NSRange(location: (view.storage.string as NSString).range(of: "zwei").location + 4, length: 0)
        XCTAssertTrue(engine.indent(by: 1))
        type("\ndrei")
        XCTAssertEqual(markdown, "- eins\n  - zwei\n  - drei\n")
        type("\n\n")
        // Return on the empty nested item moves it out one level instead of ending the list.
        let style = engine.style(of: engine.paragraph(at: view.selectedRange.location))
        XCTAssertEqual(style.type, .bullet)
        XCTAssertEqual(style.indent, 0)
    }

    func testShiftTabOffersItselfOnlyInLists() {
        open("Absatz\n- Punkt\n")
        view.selectedRange = NSRange(location: 2, length: 0)
        XCTAssertFalse(engine.canIndent)
        XCTAssertFalse(view.keyCommands?.contains { $0.input == "\t" } ?? false)
        view.selectedRange = NSRange(location: (view.storage.string as NSString).range(of: "Punkt").location, length: 0)
        XCTAssertTrue(engine.canIndent)
        XCTAssertTrue(view.keyCommands?.contains { $0.input == "\t" && $0.modifierFlags == .shift } ?? false)
    }
}
