import Foundation
import InkhashCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What copying a selection puts on the pasteboard: Markdown for inkhash and Markdown apps, RTF for
/// apps that show styles. See ADR 0063.
struct ClipboardContent {
    /// Inkhash's own type. Pasting it reads Markdown; plain text from elsewhere stays plain (ADR 0025).
    static let markdownType = "local.inkhash.markdown"

    var markdown: String
    var rtf: Data?
}

extension EditorEngine {
    /// The selection for the pasteboard. Nil without a selection.
    func clipboard(for range: NSRange) -> ClipboardContent? {
        guard range.length > 0, NSMaxRange(range) <= ns.length else { return nil }
        return ClipboardContent(markdown: markdown(of: range), rtf: rtf(of: range))
    }

    /// Whole paragraphs as blocks. Part of one paragraph only as its inline text, so half a list item
    /// does not become a list item where it is pasted.
    func markdown(of range: NSRange) -> String {
        let blocks = NoteDocument.blocks(from: host.storage.attributedSubstring(from: range), trailing: .paragraph)
        let contentRange = content(of: paragraph(at: range.location))
        let withinOne = NSIntersectionRange(contentRange, range) == range && range.length < contentRange.length
        if withinOne, let block = blocks.first, block.type != .excerpt {
            return MarkdownCodec.serializeInline(block.spans)
        }
        return MarkdownCodec.serialize(blocks)
    }

    /// The selection as it looks, without the note's indent and its drawn markers.
    private func rtf(of range: NSRange) -> Data? {
        let piece = NSMutableAttributedString(attributedString: host.storage.attributedSubstring(from: range))
        let full = NSRange(location: 0, length: piece.length)
        piece.removeAttribute(.paragraphStyle, range: full)
        piece.removeAttribute(.attachment, range: full)
        piece.enumerateAttribute(.inkhashLink, in: full) { value, run, _ in
            if let target = value as? String, let url = URL(string: target) { piece.addAttribute(.link, value: url, range: run) }
        }
        #if os(macOS)
        return piece.rtf(from: full, documentAttributes: [:])
        #else
        return try? piece.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        #endif
    }

    /// Markdown that inkhash copied, put where the selection is, as one undoable change.
    func paste(markdown: String) {
        insertMarkdown(markdown, replacing: host.selection)
        host.focus()
    }
}
