import Foundation
import InkhashCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Excerpts in the text: one attachment per paragraph. See ADR 0032 and 0037.
extension EditorEngine {
    /// True if the paragraph holds an excerpt attachment. See ADR 0032.
    func hasExcerpt(_ paragraph: NSRange) -> Bool {
        excerptAttachment(in: paragraph) != nil
    }

    private func excerptAttachment(in paragraph: NSRange) -> ExcerptAttachment? {
        guard paragraph.length > 0, NSMaxRange(paragraph) <= host.storage.length else { return nil }
        var found: ExcerptAttachment?
        host.storage.enumerateAttribute(.attachment, in: paragraph) { value, _, stop in
            if let attachment = value as? ExcerptAttachment { found = attachment; stop.pointee = true }
        }
        return found
    }

    /// The excerpt drawn under `point` (text view coordinates), if any.
    func excerpt(at point: CGPoint) -> ExcerptTarget? {
        guard ns.length > 0 else { return nil }
        let local = CGPoint(x: point.x - host.containerOrigin.x, y: point.y - host.containerOrigin.y)
        let layout = host.markers
        layout.ensureLayout(for: host.container)
        let glyph = layout.glyphIndex(for: local, in: host.container)
        let character = layout.characterIndexForGlyph(at: glyph)
        guard character < ns.length,
              let attachment = host.storage.attribute(.attachment, at: character, effectiveRange: nil) as? ExcerptAttachment else { return nil }
        let box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: host.container)
        return box.contains(local) ? attachment.target : nil
    }

    /// Puts an excerpt where the cursor stands, in a paragraph of its own. See ADR 0032.
    func insertExcerpt(_ excerpt: ExcerptTarget, label: String) {
        let line = MarkdownCodec.serialize([MarkdownCodec.excerptBlock(excerpt, label: label)])
        insertMarkdown(line.trimmingCharacters(in: .newlines), replacing: host.selection)
        host.focus()
        updateState()
    }

    /// A single pasted `![label](excerpt)` becomes an excerpt, not text with a link.
    func isExcerptLine(_ text: String) -> Bool {
        let blocks = MarkdownCodec.parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return blocks.count == 1 && MarkdownCodec.excerpt(in: blocks[0]) != nil
    }

    /// Text typed into an excerpt's paragraph goes into a new paragraph before or after it.
    func insertBesideExcerpt(_ text: String, at location: Int) -> Bool {
        let current = paragraph(at: location)
        guard style(of: current).type == .excerpt, hasExcerpt(current) else { return false }
        let contentRange = content(of: current)
        let plain = NoteDocument.typingAttributes(.paragraph)
        let insertion: NSAttributedString
        let at: Int
        let cursor: Int
        if location <= contentRange.location {
            insertion = NSAttributedString(string: text + "\n", attributes: plain)
            at = contentRange.location
            cursor = at + (text as NSString).length
        } else {
            let built = NSMutableAttributedString(string: "\n", attributes: NoteDocument.typingAttributes(BlockStyle(type: .excerpt)))
            built.append(NSAttributedString(string: text, attributes: plain))
            insertion = built
            at = NSMaxRange(contentRange)
            cursor = at + built.length
        }
        let target = NSRange(location: at, length: 0)
        edit(target, replacement: insertion.string) { host.storage.replaceCharacters(in: target, with: insertion) }
        host.selection = NSRange(location: cursor, length: 0)
        restyle(NSRange(location: at, length: insertion.length))
        applyTypingForCursor()
        publish()
        return true
    }
}
