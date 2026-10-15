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
}
