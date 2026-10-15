import AppKit
import InkhashCore
import SwiftUI
import XCTest

/// The whole note sheet on the Mac, over a library of its own. See ADR 0061, 0062 and P-061.
@MainActor
final class MacNoteSheetTests: XCTestCase {
    private var base: URL!
    private var window: NSWindow!
    private var hosting: NSView!

    override func tearDown() async throws {
        window?.close()
        if let base { try? FileManager.default.removeItem(at: base) }
        UserDefaults.standard.removeObject(forKey: TextAppearance.familyKey)
        UserDefaults.standard.removeObject(forKey: TextAppearance.sizeKey)
    }

    private func show(_ markdown: String) throws -> InkNoteTextView {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("inkhash-mac-\(UUID().uuidString)")
        let model = AppModel(base: base, legacy: nil)
        var note = Note.newText()
        note.applyMarkdown(markdown)
        model.library.add(note)
        let record = try XCTUnwrap(model.library.record(note.id))
        hosting = NSHostingView(rootView: NavigationStack { TextNoteView(note: record.note, model: model) }.environment(model))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        settle()
        return try XCTUnwrap(find(InkNoteTextView.self, in: hosting))
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    }

    private func render(_ name: String) throws {
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/inkhash-\(name).png"))
    }

    func testTasksAndTheSlashMenu() throws {
        let text = try show("# Woche\n\nNoch einer mit Text\n\n- [ ] Angebot schicken 📅 \(TaskDue.day(of: Date()))\n- [x] Milch kaufen 📅 2026-10-01\n- [ ] Ohne Datum\n")
        let target = (text.string as NSString).range(of: "Noch einer mit Text")
        window.makeFirstResponder(text)
        text.setSelectedRange(NSRange(location: NSMaxRange(target), length: 0))
        text.insertText(" /", replacementRange: text.selectedRange())
        settle()
        try render("mac-sheet")
    }

    /// Opening the menu must not scroll the note away from the cursor. See P-062.
    func testTheSlashMenuKeepsTheNoteWhereItIs() throws {
        let paragraphs = (1...60).map { "Absatz \($0) mit etwas Text" }.joined(separator: "\n\n")
        let text = try show("# Lang\n\n" + paragraphs + "\n")
        let scroll = try XCTUnwrap(find(NSScrollView.self, in: hosting))
        let target = (text.string as NSString).range(of: "Absatz 40 mit etwas Text")
        window.makeFirstResponder(text)
        text.setSelectedRange(NSRange(location: NSMaxRange(target), length: 0))
        settle()
        let glyphs = text.layoutManager!.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
        let line = text.layoutManager!.boundingRect(forGlyphRange: glyphs, in: text.textContainer!)
        let inDocument = text.convert(line, to: scroll.documentView)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, inDocument.minY - 250)))
        scroll.reflectScrolledClipView(scroll.contentView)
        settle()
        let before = scroll.contentView.bounds.origin.y
        XCTAssertGreaterThan(before, 300, "scrolled down to the paragraph")
        text.insertText(" x", replacementRange: text.selectedRange())
        settle()
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, before - 60, "typing keeps the note where it is")
        text.insertText(" /", replacementRange: text.selectedRange())
        settle()
        let after = scroll.contentView.bounds.origin.y
        XCTAssertGreaterThan(after, before - 60, "jumped from \(before) to \(after)")
        try render("mac-slash-scrolled")
    }

    func testTypingOutOfSightScrollsToTheCursor() throws {
        let paragraphs = (1...60).map { "Absatz \($0) mit etwas Text" }.joined(separator: "\n\n")
        let text = try show("# Lang\n\n" + paragraphs + "\n")
        let scroll = try XCTUnwrap(find(NSScrollView.self, in: hosting))
        XCTAssertLessThan(scroll.contentView.bounds.origin.y, 100, "opens at the top")
        let target = (text.string as NSString).range(of: "Absatz 55 mit etwas Text")
        window.makeFirstResponder(text)
        text.setSelectedRange(NSRange(location: NSMaxRange(target), length: 0))
        text.insertText(" x", replacementRange: text.selectedRange())
        settle()
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 1000)
    }

    func testANewFontAppliesToTheOpenNote() throws {
        let text = try show("Text\n")
        let before = try XCTUnwrap(text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        UserDefaults.standard.set(TextFamily.serif.rawValue, forKey: TextAppearance.familyKey)
        UserDefaults.standard.set(22.0, forKey: TextAppearance.sizeKey)
        settle()
        let after = try XCTUnwrap(text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(after.pointSize, before.pointSize * 22 / 17, accuracy: 0.1)
        XCTAssertNotEqual(after.fontName, before.fontName)
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let found = find(type, in: sub) { return found } }
        return nil
    }
}
