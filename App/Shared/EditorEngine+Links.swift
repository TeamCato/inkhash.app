import Foundation
import InkhashCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Links in the text: `[[` to another note and `/Link`. See ADR 0024, 0027 and 0031.
extension EditorEngine {
    var isInTable: Bool {
        style(of: paragraph(at: host.selection.location)).type == .tableRow
    }

    /// The link whose text the cursor touches, on either side.
    func link(around location: Int) -> String? {
        for index in [location, location - 1] where index >= 0 && index < host.storage.length {
            if let target = host.storage.attribute(.inkhashLink, at: index, effectiveRange: nil) as? String { return target }
        }
        return nil
    }

    /// `[[abc` right before the cursor, without a closing bracket or a line break: "abc".
    func openNoteQuery(before location: Int, in contentRange: NSRange) -> String? {
        let head = NSRange(location: contentRange.location, length: location - contentRange.location)
        guard head.length >= 2 else { return nil }
        let opener = ns.range(of: "[[", options: .backwards, range: head)
        guard opener.location != NSNotFound else { return nil }
        let query = ns.substring(with: NSRange(location: NSMaxRange(opener), length: location - NSMaxRange(opener)))
        guard !query.contains("]"), query.count <= 60 else { return nil }
        if let suppressedNoteQuery, suppressedNoteQuery == query { return nil }
        suppressedNoteQuery = nil
        return query
    }

    /// Replaces `[[query` before the cursor with `title` linked to `target`.
    func insertNoteLink(title: String, target: String) {
        let cursor = host.selection.location
        let contentRange = content(of: paragraph(at: cursor))
        let head = NSRange(location: contentRange.location, length: cursor - contentRange.location)
        let opener = ns.range(of: "[[", options: .backwards, range: head)
        guard opener.location != NSNotFound else { return }
        insertLink(label: title, target: target, replacing: NSRange(location: opener.location, length: cursor - opener.location))
    }

    /// Puts `label` linked to `target` where the cursor stands, as asked by `/Link`. See ADR 0031.
    func insertLink(label: String, target: String) {
        let selection = host.selection
        let range = NSRange(location: min(selection.location, ns.length), length: min(selection.length, ns.length - min(selection.location, ns.length)))
        insertLink(label: label, target: target, replacing: range)
    }

    /// `label` as a link, then a plain space so typing goes on outside the link.
    private func insertLink(label: String, target: String, replacing range: NSRange) {
        var attributes = host.typing
        for key in RichText.linkAttributeKeys { attributes.removeValue(forKey: key) }
        attributes.merge(RichText.linkAttributes(target)) { _, new in new }
        let linked = NSMutableAttributedString(string: label, attributes: attributes)
        var plain = host.typing
        for key in RichText.linkAttributeKeys { plain.removeValue(forKey: key) }
        plain[.foregroundColor] = RichText.inkColor
        linked.append(NSAttributedString(string: " ", attributes: plain))
        edit(range, replacement: linked.string) { host.storage.replaceCharacters(in: range, with: linked) }
        host.selection = NSRange(location: range.location + linked.length, length: 0)
        host.typing = plain
        host.focus()
        publish()
    }

    func escapeNoteLink() {
        let cursor = host.selection.location
        let contentRange = content(of: paragraph(at: cursor))
        let head = NSRange(location: contentRange.location, length: cursor - contentRange.location)
        let opener = ns.range(of: "[[", options: .backwards, range: head)
        if opener.location != NSNotFound {
            suppressedNoteQuery = ns.substring(with: NSRange(location: NSMaxRange(opener), length: cursor - NSMaxRange(opener)))
        }
        updateState()
    }
}
