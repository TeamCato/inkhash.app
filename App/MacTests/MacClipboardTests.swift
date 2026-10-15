import AppKit
import InkhashCore
import XCTest

/// Copy and paste keep the style on the Mac. See ADR 0063.
@MainActor
final class MacClipboardTests: XCTestCase {
    private var view: InkNoteTextView!
    private var engine: EditorEngine!
    private var coordinator: MacNoteCoordinator!
    private var window: NSWindow!
    private var board: NSPasteboard!

    override func tearDown() async throws {
        board?.releaseGlobally()
        window?.close()
    }

    private func open(_ markdown: String) {
        let (storage, _, container) = makeTextStack()
        view = withExtendedLifetime(storage) { InkNoteTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 400), textContainer: container) }
        view.ownedStorage = storage
        view.isRichText = true
        view.allowsUndo = true
        engine = EditorEngine(host: view, blocks: MarkdownCodec.parse(markdown), source: .none)
        view.engine = engine
        coordinator = MacNoteCoordinator()
        coordinator.engine = engine
        view.delegate = coordinator
        board = NSPasteboard(name: NSPasteboard.Name("inkhash-test-\(UUID().uuidString)"))
        view.pasteboard = board
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
    }

    private var markdown: String {
        MarkdownCodec.serialize(NoteDocument.blocks(from: view.textStorage!, trailing: .paragraph))
    }

    func testCopiedBlocksComeBackWithTheirStyle() {
        open("# Plan\n- [x] Erledigt\n- **fett**\n\n")
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        view.copy(nil)
        let once = "# Plan\n\n- [x] Erledigt\n\n- **fett**\n"
        XCTAssertEqual(board.string(forType: .string), once)
        XCTAssertNotNil(board.data(forType: .rtf))
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.paste(nil)
        XCTAssertEqual(markdown, once + "\n" + once)
    }

    func testCutThenPasteGivesTheSameNote() {
        open("Text **fett** und *kursiv*\n")
        let whole = (view.string as NSString).range(of: "Text fett und kursiv")
        view.setSelectedRange(whole)
        view.cut(nil)
        XCTAssertEqual(view.string.trimmingCharacters(in: .newlines), "")
        view.paste(nil)
        XCTAssertEqual(markdown, "Text **fett** und *kursiv*\n")
    }
}
