import Foundation
import InkhashCore
import Observation

/// The find bar of one open text note: Cmd+F opens it, Return and Cmd+G step forward, Shift and Cmd+Shift+G back,
/// Escape closes it and leaves the current match selected. See ADR 0084.
@MainActor
@Observable
final class NoteFinder {
    @ObservationIgnored weak var engine: EditorEngine?
    /// Nil while the bar is closed.
    private(set) var find: NoteFind?
    /// Bumped whenever the bar should take the keyboard, also when it is open already.
    private(set) var focusToken = 0
    /// What the bar asked for last time, offered again when it opens without a selection.
    @ObservationIgnored private var lastQuery = ""

    var isOpen: Bool { find != nil }

    func open() {
        let query = engine?.selectedQuery ?? find?.query ?? lastQuery
        run(query, anchor: engine?.cursor ?? 0, reveal: true)
        focusToken += 1
    }

    func setQuery(_ query: String) {
        guard query != find?.query else { return }
        run(query, anchor: find?.currentRange?.location ?? engine?.cursor ?? 0, reveal: true)
    }

    func next() {
        guard find != nil else { return open() }
        find?.next()
        show(reveal: true)
    }

    func previous() {
        guard find != nil else { return open() }
        find?.previous()
        show(reveal: true)
    }

    func close() {
        guard let find else { return }
        lastQuery = find.query
        self.find = nil
        engine?.endFind(selecting: find.currentRange)
    }

    /// The text changed under an open bar: the marks follow it, the view does not jump.
    func textChanged() {
        guard let find else { return }
        run(find.query, anchor: find.currentRange?.location ?? 0, reveal: false)
    }

    private func run(_ query: String, anchor: Int, reveal: Bool) {
        var next = find ?? NoteFind()
        next.update(query: query, in: engine?.text ?? "", anchor: anchor)
        find = next
        show(reveal: reveal)
    }

    private func show(reveal: Bool) {
        guard let find else { return }
        engine?.showFind(find, reveal: reveal)
    }
}
