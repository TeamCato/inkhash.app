import InkhashCore
import UIKit
import XCTest
@testable import Inkhash

@MainActor
final class TableEditingTests: EditorTestCase {
    func testBarsAndReturnStartATable() {
        open()
        type("| Name | Wert |\n")
        XCTAssertEqual(types.first, .tableRow, view.storage.string.debugDescription)
        type("a|b")
        XCTAssertEqual(markdown, "| Name | Wert |\n| --- | --- |\n| a | b |\n")
    }

    func testSlashTableStartsATable() {
        open()
        type("/tab")
        XCTAssertTrue(engine.slashOpen)
        slash(.table)
        type("Name|Wert\n")
        XCTAssertEqual(types.first, .tableRow, view.storage.string.debugDescription)
        XCTAssertTrue(markdown.hasPrefix("| Name | Wert |\n| --- | --- |\n"), markdown)
    }

    func testSlashTableInAParagraphInTheMiddle() {
        open("Vorher\n\nNachher\n")
        view.selectedRange = NSRange(location: 6, length: 0)
        type("\n/tab")
        slash(.table)
        type("A|B")
        XCTAssertEqual(markdown, "Vorher\n\n| A | B |\n| --- | --- |\n\nNachher\n")
    }

    func testBarsAndReturnAfterText() {
        open("Vorher\n")
        view.selectedRange = NSRange(location: view.storage.length, length: 0)
        type("\n| A | B |\n")
        XCTAssertTrue(types.contains(.tableRow), view.storage.string.debugDescription)
    }
}

@MainActor
final class HarnessTests: EditorTestCase {
    func testShortcutRunsThroughTheDelegate() {
        open()
        type("# Titel")
        XCTAssertEqual(markdown, "# Titel\n")
    }
}

@MainActor
final class TableFormatEditingTests: EditorTestCase {
    func testAlignmentAndZebraReachTheMarkdown() {
        open("| A | B |\n| --- | --- |\n| 1 | 2 |\n")
        view.selectedRange = NSRange(location: 2, length: 0) // in the header, second column
        XCTAssertEqual(engine.tableAtCursor?.column, 1)
        engine.changeTable { format, column, columns in format.setAlignment(.right, of: column, columns: columns) }
        engine.changeTable { format, _, _ in format.zebra = true }
        XCTAssertEqual(markdown, "| A | B |\n| --- | ---: |\n| 1 | 2 |\n<!-- inkhash:table zebra -->\n")
    }

    func testFormatSurvivesNewRows() {
        open("| A | B |\n| --- | :---: |\n| 1 | 2 |\n")
        view.selectedRange = NSRange(location: view.storage.length, length: 0)
        type("\t3|4")
        XCTAssertEqual(markdown, "| A | B |\n| --- | :---: |\n| 1 | 2 |\n| 3 | 4 |\n")
    }
}

@MainActor
final class ExcerptEditingTests: EditorTestCase {
    private let target = "inkhash://note/6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10/page/0a0b0c0d-1111-2222-3333-444455556666?rect=10,20,300,120"

    func testTypingBesideAnExcerptMakesANewParagraph() {
        open("![Skizze](\(target))\n")
        view.selectedRange = NSRange(location: 1, length: 0)
        type("danach")
        XCTAssertEqual(markdown, "![Skizze](\(target))\n\ndanach\n")
        view.selectedRange = NSRange(location: 0, length: 0)
        type("davor")
        XCTAssertEqual(markdown, "davor\n\n![Skizze](\(target))\n\ndanach\n")
    }

    func testPastedLineBecomesAnExcerpt() {
        open("Text")
        view.selectedRange = NSRange(location: 4, length: 0)
        type("\n")
        XCTAssertTrue(coordinatorAccepts("![Skizze](\(target))") == false)
        XCTAssertEqual(types, [.paragraph, .excerpt])
    }

    func testBackspaceAtTheStartDoesNotMergeIntoTheLineAbove() {
        open("Oben\n\n![Skizze](\(target))\n")
        view.selectedRange = NSRange(location: 5, length: 0)
        XCTAssertTrue(engine.backspaceAtStart())
        XCTAssertEqual(types, [.paragraph, .excerpt])
        XCTAssertEqual(view.selectedRange.location, 4)
    }

    func testTextExcerptRoundTripsThroughTheEditor() {
        let text = TextExcerpt(noteID: UUID(), from: "Erster Absatz", to: "Letzter")
        open("Davor\n\n![Protokoll](\(text.target))\n")
        XCTAssertEqual(types, [.paragraph, .excerpt])
        XCTAssertEqual(markdown, "Davor\n\n![Protokoll](\(text.target))\n")
    }

    func testInlineSlashKeepsTheText() {
        open("Einkaufen ")
        view.selectedRange = NSRange(location: 10, length: 0)
        type("/auf")
        XCTAssertTrue(engine.slashOpen)
        slash(.checkbox)
        XCTAssertEqual(markdown, "- [ ] Einkaufen \n")
    }

    func testSlashInsideAWordStaysText() {
        open("und")
        view.selectedRange = NSRange(location: 3, length: 0)
        type("/oder")
        XCTAssertFalse(engine.slashOpen)
    }
}
