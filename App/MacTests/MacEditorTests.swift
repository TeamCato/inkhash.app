import AppKit
import InkhashCore
import XCTest

/// The Mac text view and engine, as `MacNoteText` builds them, in a window of their own.
@MainActor
final class MacEditorTests: XCTestCase {
    private var view: InkNoteTextView!
    private var engine: EditorEngine!
    private var window: NSWindow!

    private func open(_ markdown: String) {
        let (storage, _, container) = makeTextStack()
        view = withExtendedLifetime(storage) { InkNoteTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 600), textContainer: container) }
        view.ownedStorage = storage
        view.isRichText = true
        view.allowsUndo = true
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.isVerticallyResizable = false
        engine = EditorEngine(host: view, blocks: MarkdownCodec.parse(markdown), source: .none)
        view.engine = engine
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
    }

    func testRender() throws {
        open("""
        Absatz
        - Punkt
        - [ ] Angebot schicken 📅 \(TaskDue.day(of: Date()))
        - [x] Milch kaufen 📅 2026-10-01
        - [ ] Ohne Datum

        """)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/inkhash-mac-editor.png"))
        print("CARET line1", engine.caretRect(0), "mid", engine.caretRect(3), "line2", engine.caretRect(9))
    }

    /// Finding marks every match, the current one strongest, and leaves it selected on close. See ADR 0084.
    func testFindMarksMatchesAndSelectsCurrentOnClose() throws {
        open("""
        # Einkauf
        Äpfel und Birnen, dazu noch äpfel
        - Apfelsaft

        """)
        let finder = NoteFinder()
        finder.engine = engine
        view.setSelectedRange(NSRange(location: 0, length: 0))
        finder.open()
        finder.setQuery("apfel")
        XCTAssertEqual(finder.find?.matches.count, 3)
        XCTAssertEqual(view.markers.findMatches.count, 3)
        finder.next()
        XCTAssertEqual(finder.find?.countLabel, "2 von 3")
        let current = try XCTUnwrap(view.markers.findCurrent)
        XCTAssertEqual((view.string as NSString).substring(with: current), "äpfel")
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/inkhash-mac-find.png"))
        finder.close()
        XCTAssertTrue(view.markers.findMatches.isEmpty)
        XCTAssertEqual(view.selectedRange(), current)
        XCTAssertFalse(finder.isOpen)
    }

    /// A selected word becomes the query when the bar opens.
    func testFindStartsWithTheSelection() {
        open("Treffen am Montag, Treffen am Freitag\n")
        let finder = NoteFinder()
        finder.engine = engine
        view.setSelectedRange(NSRange(location: 0, length: 7))
        finder.open()
        XCTAssertEqual(finder.find?.query, "Treffen")
        XCTAssertEqual(finder.find?.countLabel, "1 von 2")
    }
}
