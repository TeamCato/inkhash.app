import InkhashCore
import UIKit
import XCTest
@testable import Inkhash

/// Lists and tasks in the flow of the text, menus at the cursor, the chosen font. See ADR 0061, 0062.
@MainActor
final class EditorLookTests: EditorTestCase {
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: TextAppearance.familyKey)
        UserDefaults.standard.removeObject(forKey: TextAppearance.sizeKey)
        try await super.tearDown()
    }

    private func paragraphStyle(at location: Int) -> NSParagraphStyle? {
        view.storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    func testListItemsStandOneStepRightOfParagraphs() throws {
        open("Absatz\n- Punkt\n- [ ] Aufgabe\n")
        let paragraph = try XCTUnwrap(paragraphStyle(at: 0))
        let bullet = try XCTUnwrap(paragraphStyle(at: 7))
        let task = try XCTUnwrap(paragraphStyle(at: 13))
        XCTAssertEqual(paragraph.headIndent, NoteDocument.gutter)
        XCTAssertGreaterThan(bullet.firstLineHeadIndent, paragraph.firstLineHeadIndent + 15)
        XCTAssertEqual(bullet.headIndent, bullet.firstLineHeadIndent, "wrapped lines hang under the text")
        XCTAssertGreaterThan(task.firstLineHeadIndent, paragraph.firstLineHeadIndent + 15)
    }

    func testTheBoxIsHitWhereParagraphsBegin() {
        open("- [ ] Aufgabe\n")
        let point = CGPoint(x: view.textContainerInset.left + NoteDocument.gutter + 6, y: view.textContainerInset.top + 12)
        XCTAssertNotNil(engine.checkbox(at: point))
        let text = CGPoint(x: view.textContainerInset.left + NoteDocument.gutter + 80, y: view.textContainerInset.top + 12)
        XCTAssertNil(engine.checkbox(at: text))
    }

    func testADoneTaskIsStruckThroughAndItsDayIsACapsule() {
        open("- [x] Angebot 📅 2026-10-20\n")
        XCTAssertNotNil(view.storage.attribute(.strikethroughStyle, at: 2, effectiveRange: nil))
        let ns = view.storage.string as NSString
        let marker = ns.range(of: TaskDue.marker)
        XCTAssertEqual(view.storage.attribute(.inkhashDue, at: marker.location, effectiveRange: nil) as? String, "2026-10-20")
        XCTAssertNil(view.storage.attribute(.strikethroughStyle, at: marker.location, effectiveRange: nil), "the capsule is not struck through")
        XCTAssertNil(view.storage.attribute(.inkhashDue, at: 2, effectiveRange: nil))
        XCTAssertEqual(markdown, "- [x] Angebot 📅 2026-10-20\n", "display only")
    }

    func testOpeningATaskTakesTheStrikeAway() {
        open("- [x] Angebot\n")
        XCTAssertNotNil(view.storage.attribute(.strikethroughStyle, at: 2, effectiveRange: nil))
        engine.toggleChecked(engine.paragraph(at: 0))
        XCTAssertNil(view.storage.attribute(.strikethroughStyle, at: 2, effectiveRange: nil))
    }

    func testTypingAfterADayIsPlainText() {
        open("- [ ] Angebot 📅 2026-10-20\n")
        let end = (view.storage.string as NSString).length - 1
        view.selectedRange = NSRange(location: end, length: 0)
        engine.selectionChanged()
        XCTAssertNil(view.typingAttributes[.inkhashDue])
    }

    func testTheCaretIsWhereTheCursorStandsNotAtTheLineStart() {
        open("eins zwei drei\nvier\n")
        view.selectedRange = NSRange(location: 0, length: 0)
        engine.selectionChanged()
        let start = engine.caretRect(0)
        let middle = engine.caretRect(5)
        let second = engine.caretRect(15)
        XCTAssertGreaterThan(middle.minX, start.minX + 20)
        XCTAssertEqual(middle.minY, start.minY, accuracy: 0.5)
        XCTAssertGreaterThan(second.minY, start.maxY)
        XCTAssertLessThan(start.height, 30, "the text's height, not the line with its spacing")
    }

    func testTheSlashMenuOpensAtTheCursor() {
        open("eins zwei\n")
        view.selectedRange = NSRange(location: 9, length: 0)
        engine.selectionChanged()
        type(" /")
        XCTAssertGreaterThan(engine.caretRect(view.selectedRange.location).minX, NoteDocument.gutter + 40)
    }

    func testTheChosenSizeScalesTheText() {
        open("Text\n")
        let before = EditorFont.size(for: .paragraph)
        UserDefaults.standard.set(TextAppearance.defaultSize + 4, forKey: TextAppearance.sizeKey)
        XCTAssertEqual(EditorFont.size(for: .paragraph), before * (21 / 17), accuracy: 0.1)
        engine.textSizeChanged()
        let font = view.storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertEqual(font?.pointSize ?? 0, before * (21 / 17), accuracy: 0.1)
    }

    func testTheChosenFamilyAppliesToTextButNotToHeadings() {
        UserDefaults.standard.set(TextFamily.mono.rawValue, forKey: TextAppearance.familyKey)
        open("# Titel\nText\n")
        let heading = view.storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let text = view.storage.attribute(.font, at: 7, effectiveRange: nil) as? UIFont
        XCTAssertTrue(text?.fontName.contains("Mono") ?? false, text?.fontName ?? "")
        XCTAssertFalse(heading?.fontName.contains("Mono") ?? true, heading?.fontName ?? "")
    }
}
