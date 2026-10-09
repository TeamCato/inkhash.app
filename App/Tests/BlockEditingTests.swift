import InkhashCore
import UIKit
import XCTest
@testable import Inkhash

/// Block shortcuts, Return and Backspace, typed through the delegate like the keyboard does.
@MainActor
final class BlockEditingTests: EditorTestCase {
    /// P-028: the marker goes in the same keystroke, it never stays in the text.
    func testShortcutsTurnTheLineAndLeaveNoMarker() {
        for (typed, expected, block) in [
            ("# Titel", "# Titel\n", BlockType.heading1),
            ("## Mitte", "## Mitte\n", .heading2),
            ("### Klein", "### Klein\n", .heading3),
            ("- Punkt", "- Punkt\n", .bullet),
            ("* Punkt", "- Punkt\n", .bullet),
            ("1. Erstens", "1. Erstens\n", .numbered),
            ("x Aufgabe", "- [ ] Aufgabe\n", .checkbox),
            ("[] Aufgabe", "- [ ] Aufgabe\n", .checkbox),
        ] {
            open()
            type(typed)
            XCTAssertEqual(markdown, expected, typed)
            XCTAssertEqual(types.first, block, typed)
            XCTAssertFalse(view.storage.string.hasPrefix("#") || view.storage.string.hasPrefix("-"), typed)
        }
    }

    func testAHashtagIsNoHeading() {
        open()
        type("#idee und mehr")
        XCTAssertEqual(markdown, "#idee und mehr\n")
        XCTAssertEqual(types.first, .paragraph)
    }

    /// P-040: Return in a list goes on in the list, and the new item keeps its style while typing.
    func testReturnContinuesListsAndTasks() {
        open()
        type("- eins\nzwei\ndrei")
        XCTAssertEqual(markdown, "- eins\n- zwei\n- drei\n")
        open()
        type("x kaufen\nputzen")
        XCTAssertEqual(markdown, "- [ ] kaufen\n- [ ] putzen\n")
        open()
        type("1. a\nb")
        XCTAssertEqual(markdown, "1. a\n2. b\n")
    }

    func testReturnOnAnEmptyItemLeavesTheList() {
        open()
        type("- eins\n\nweiter")
        XCTAssertEqual(markdown, "- eins\n\nweiter\n")
        XCTAssertEqual(types.last, .paragraph)
    }

    func testReturnAfterAHeadingIsAParagraph() {
        open()
        type("# Titel\nText")
        XCTAssertEqual(markdown, "# Titel\n\nText\n")
    }

    func testBackspaceAtTheStartOfAnItemMakesItAParagraph() {
        open("- eins\n")
        view.selectedRange = NSRange(location: 0, length: 0)
        XCTAssertTrue(engine.backspaceAtStart())
        XCTAssertEqual(markdown, "eins\n")
    }

    func testToggleCheckedTicksATask() {
        open("- [ ] kaufen\n")
        engine.toggleChecked(engine.paragraph(at: 0))
        XCTAssertEqual(markdown, "- [x] kaufen\n")
        engine.toggleChecked(engine.paragraph(at: 0))
        XCTAssertEqual(markdown, "- [ ] kaufen\n")
    }

    func testSettingTheTypeFromTheMenu() {
        open("Text\n")
        view.selectedRange = NSRange(location: 1, length: 0)
        engine.setType(.heading2)
        XCTAssertEqual(markdown, "## Text\n")
        engine.setType(.paragraph)
        XCTAssertEqual(markdown, "Text\n")
    }

    /// P-028, second half: after a closed inline marker, typing goes on plain.
    func testTypingAfterBoldIsPlain() {
        open()
        type("**fett** normal")
        XCTAssertEqual(markdown, "**fett** normal\n")
    }

    func testBoldFromTheSelection() {
        open("eins zwei\n")
        view.selectedRange = NSRange(location: 5, length: 4)
        engine.selectionChanged()
        engine.toggle(.toggleBold)
        XCTAssertEqual(markdown, "eins **zwei**\n")
    }

    func testCodeBlockKeepsItsLines() {
        open()
        type("``` let a = 1\nlet b = 2")
        XCTAssertTrue(markdown.contains("```\nlet a = 1\nlet b = 2\n```"), markdown)
    }

    func testSlashMenuMakesAHeadingAndClosesOnEscape() {
        open()
        type("/üb")
        XCTAssertTrue(engine.slashOpen)
        engine.escapeSlash()
        XCTAssertFalse(engine.slashOpen)
        XCTAssertEqual(markdown, "/üb\n")
    }

    /// P-037: measuring a width never changes the text view's own container.
    func testMeasuringLeavesTheContainerAlone() {
        open(String(repeating: "Wort ", count: 80))
        let width = view.textContainer.size.width
        let narrow = engine.height(for: 120)
        let wide = engine.height(for: 600)
        XCTAssertGreaterThan(narrow, wide)
        XCTAssertEqual(view.textContainer.size.width, width)
        _ = engine.height(for: 0)
        XCTAssertEqual(view.textContainer.size.width, width)
    }
}

@MainActor
final class LinkEditingTests: EditorTestCase {
    func testDoubleBracketOpensTheNoteMenuAndInsertsALink() {
        open()
        type("Siehe [[pla")
        XCTAssertTrue(engine.noteLinkOpen)
        let id = UUID().uuidString.lowercased()
        engine.insertNoteLink(title: "Plan", target: "inkhash://note/\(id)")
        XCTAssertFalse(engine.noteLinkOpen)
        type("weiter")
        XCTAssertEqual(markdown, "Siehe [Plan](inkhash://note/\(id)) weiter\n")
    }

    func testEscapeKeepsTheBracketsAsText() {
        open()
        type("[[abc")
        engine.escapeNoteLink()
        XCTAssertFalse(engine.noteLinkOpen)
        XCTAssertEqual(markdown, "[[abc\n")
    }

    func testClosedBracketsAreNoQuery() {
        open()
        type("[[abc]] danach")
        XCTAssertFalse(engine.noteLinkOpen)
    }

    func testLinkFromTheSlashMenuAtTheCursor() {
        open("Vorher \n")
        view.selectedRange = NSRange(location: 7, length: 0)
        engine.insertLink(label: "Seite", target: "https://inkhash.app")
        XCTAssertEqual(markdown, "Vorher [Seite](https://inkhash.app) \n")
    }

    func testLinkOnASelectionAndOffAgain() {
        open("eins zwei\n")
        view.selectedRange = NSRange(location: 5, length: 4)
        engine.selectionChanged()
        engine.setLink("https://inkhash.app")
        XCTAssertEqual(markdown, "eins [zwei](https://inkhash.app)\n")
        view.selectedRange = NSRange(location: 5, length: 4)
        engine.selectionChanged()
        engine.setLink(nil)
        XCTAssertEqual(markdown, "eins zwei\n")
    }
}
