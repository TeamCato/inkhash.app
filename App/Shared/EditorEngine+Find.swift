import Foundation
import InkhashCore

/// The editor's side of finding in the open note: marks the matches, shows the current one. See ADR 0084.
extension EditorEngine {
    var text: String { ns as String }

    /// The selection as a query: one line of text, nothing longer than a sentence.
    var selectedQuery: String? {
        let selection = host.selection
        guard selection.length > 0, selection.length <= 200, NSMaxRange(selection) <= ns.length else { return nil }
        let selected = ns.substring(with: selection)
        guard !selected.contains(where: \.isNewline), !selected.allSatisfy(\.isWhitespace) else { return nil }
        return selected
    }

    var cursor: Int { host.selection.location }

    /// Marks `matches` and scrolls the current one into sight. The selection stays where it is.
    func showFind(_ find: NoteFind, reveal: Bool) {
        let length = ns.length
        host.markers.findMatches = find.matches.filter { NSMaxRange($0) <= length }
        host.markers.findCurrent = find.currentRange.flatMap { NSMaxRange($0) <= length ? $0 : nil }
        host.contentChanged()
        if reveal, let current = host.markers.findCurrent { host.reveal(rect(for: current)) }
    }

    /// Takes the marks away. With a range, it becomes the selection and the text gets the focus.
    func endFind(selecting range: NSRange?) {
        host.markers.findMatches = []
        host.markers.findCurrent = nil
        host.contentChanged()
        guard let range, NSMaxRange(range) <= ns.length else { return }
        host.selection = range
        host.focus()
        selectionChanged()
    }

    private func rect(for range: NSRange) -> CGRect {
        let layout = host.markers
        layout.ensureLayout(for: host.container)
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return caretRect(range.location) }
        return layout.boundingRect(forGlyphRange: glyphs, in: host.container)
            .offsetBy(dx: host.containerOrigin.x, dy: host.containerOrigin.y)
    }
}
