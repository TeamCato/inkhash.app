import InkhashCore
import UIKit
import XCTest
@testable import Inkhash

/// A real text view and engine, typed into like the keyboard does: through the delegate.
@MainActor
class EditorTestCase: XCTestCase {
    var view: InkNoteTextView!
    var engine: EditorEngine!
    private var coordinator: IOSNoteCoordinator!
    private var window: UIWindow!

    func open(_ markdown: String = "") {
        let (storage, _, container) = makeTextStack()
        view = InkNoteTextView(frame: CGRect(x: 0, y: 0, width: 640, height: 400), textContainer: container)
        view.ownedStorage = storage
        engine = EditorEngine(host: view, blocks: MarkdownCodec.parse(markdown), source: .none)
        view.engine = engine
        coordinator = IOSNoteCoordinator()
        coordinator.engine = engine
        view.delegate = coordinator
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.addSubview(view)
        window.makeKeyAndVisible()
        view.becomeFirstResponder()
    }

    /// Types `text` character by character, Return as `\n`, like the software keyboard: the delegate is
    /// asked first, and only text it allows is inserted. `insertText` alone skips the delegate.
    func type(_ text: String) {
        for character in text {
            let piece = String(character)
            if coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: piece) {
                view.insertText(piece)
            }
        }
    }

    /// Offers `text` as one piece, like a paste. True if the text view would insert it as typed.
    func coordinatorAccepts(_ text: String) -> Bool {
        let accepted = coordinator.textView(view, shouldChangeTextIn: view.selectedRange, replacementText: text)
        if accepted { view.insertText(text) }
        return accepted
    }

    /// Picks a command from the open `/` menu.
    func slash(_ command: SlashCommand) {
        engine.applySlash(command)
    }

    var markdown: String {
        MarkdownCodec.serialize(NoteDocument.blocks(from: view.storage, trailing: .paragraph))
    }

    var types: [BlockType] {
        NoteDocument.blocks(from: view.storage, trailing: .paragraph).map(\.type)
    }
}
