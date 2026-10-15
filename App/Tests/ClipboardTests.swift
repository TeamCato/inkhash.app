import InkhashCore
import UIKit
import XCTest
@testable import Inkhash

/// Copy and paste keep the style. See ADR 0063.
@MainActor
final class ClipboardTests: EditorTestCase {
    private var board: UIPasteboard!

    override func open(_ markdown: String = "") {
        super.open(markdown)
        board = UIPasteboard.withUniqueName()
        view.pasteboard = board
    }

    override func tearDown() async throws {
        if let board { UIPasteboard.remove(withName: board.name) }
        try await super.tearDown()
    }

    private func select(_ text: String) {
        view.selectedRange = (view.storage.string as NSString).range(of: text)
        engine.selectionChanged()
    }

    private func cursor(at location: Int) {
        view.selectedRange = NSRange(location: location, length: 0)
        engine.selectionChanged()
    }

    func testCopiedBlocksComeBackWithTheirStyle() {
        open("# Plan\n- [ ] Angebot 📅 2026-10-20\n- **fett** und *kursiv*\n\n")
        view.selectedRange = NSRange(location: 0, length: (view.storage.string as NSString).length)
        engine.selectionChanged()
        view.copy(nil)
        cursor(at: (view.storage.string as NSString).length)
        view.paste(nil)
        let once = "# Plan\n\n- [ ] Angebot 📅 2026-10-20\n\n- **fett** und *kursiv*\n"
        XCTAssertEqual(markdown, once + "\n" + once, "the heading starts its own line after the list")
    }

    func testPartOfAParagraphIsPastedInline() {
        open("- **fett** und mehr\n\nZiel \n")
        select("fett und")
        view.copy(nil)
        XCTAssertEqual(board.string, "**fett** und")
        cursor(at: (view.storage.string as NSString).length)
        view.paste(nil)
        XCTAssertEqual(markdown, "- **fett** und mehr\n\nZiel **fett** und\n", "no new list item")
    }

    func testThePasteboardHoldsMarkdownAndRTF() throws {
        open("Text **fett**\n")
        select("Text fett")
        view.copy(nil)
        XCTAssertEqual(board.string, "Text **fett**\n")
        XCTAssertNotNil(board.data(forPasteboardType: ClipboardContent.markdownType))
        XCTAssertNotNil(board.data(forPasteboardType: "public.rtf"))
    }

    func testCutKeepsTheStyleAndCanBeUndone() {
        open("Text **fett**\n")
        select("Text fett")
        view.cut(nil)
        XCTAssertEqual(view.storage.string, "")
        view.paste(nil)
        XCTAssertEqual(markdown, "Text **fett**\n")
    }

    func testTextFromOtherAppsStaysPlain() {
        open("Ziel\n")
        board.setItems([["public.utf8-plain-text": "fremd"]])
        cursor(at: 4)
        view.paste(nil)
        XCTAssertEqual(markdown, "Ziel\n", "UIKit's own paste reads the general pasteboard, not this one")
    }
}
