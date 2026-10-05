import InkhashCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The text view the engine edits. One per note, see ADR 0025.
@MainActor
protocol EditorHost: AnyObject {
    var storage: NSTextStorage { get }
    var markers: MarkerLayoutManager { get }
    var container: NSTextContainer { get }
    var containerOrigin: CGPoint { get }
    var selection: NSRange { get set }
    var typing: [NSAttributedString.Key: Any] { get set }
    /// True while an input method is composing text; restyling then would break the composition.
    var isComposing: Bool { get }
    /// Runs `body`, which edits the storage, as one undoable change where the platform allows it.
    func performEdit(_ range: NSRange, replacement: String?, _ body: () -> Void)
    func focus()
    func contentChanged()
}

/// What the sheet needs to know about the editor: the selection, the block at the cursor, menus and where to put them.
struct EditorState: Equatable {
    var selection: InlineSelection = .none
    var blockType: BlockType = .paragraph
    var slashQuery: String?
    /// The `/` stands after text in its paragraph: the menu offers only what fits there.
    var slashInline = false
    /// Nothing but the `/` token is in the paragraph: blocks that need a line of their own fit.
    var slashLineEmpty = false
    /// Line of the cursor, in the text view's coordinates.
    var caret: CGRect = .zero
    /// First line of the selection, in the text view's coordinates. Nil without a selection.
    var selectionRect: CGRect?
    /// Text after an open `[[` before the cursor: the note link menu is open. See ADR 0027.
    var noteQuery: String?
    /// Target of the link the cursor stands in, so the sheet can offer to follow it.
    var caretLink: String?
    /// The table the cursor is in: its format, the cursor's column and the column count. See ADR 0036.
    var table: TableFormat?
    var tableColumn = 0
    var tableColumns = 0
}

/// Editing rules for a whole note in one text view. Both platforms forward their delegate calls here.
@MainActor
final class EditorEngine {
    unowned let host: EditorHost
    weak var session: TextSession?

    private(set) var slashOpen = false
    /// Style of the empty last paragraph. It has no character to carry its attributes.
    private var trailing = BlockStyle.paragraph
    private var programmatic = false
    private var pendingRange: NSRange?
    /// The open `/` token, from the slash to the cursor.
    private var slashRange: NSRange?
    /// The token Escape closed, as location and text, so it stays closed until it changes.
    private var suppressedSlash: String?
    /// Width the table tab stops were laid out for.
    private var tableWidth: CGFloat = 0
    private(set) var noteLinkOpen = false
    private var suppressedNoteQuery: String?
    /// Set when the text view inserts a newline itself; styles of the two halves follow in `didChange`.
    private var pendingNewline: (location: Int, atStart: Bool, upper: BlockStyle, below: BlockStyle)?

    /// Where excerpts find their pages. See ADR 0032.
    let source: ExcerptSource

    init(host: EditorHost, blocks: [Block], source: ExcerptSource) {
        self.host = host
        self.source = source
        trailing = NoteDocument.trailingStyle(of: blocks)
        host.markers.trailing = trailing
        host.storage.setAttributedString(NoteDocument.attributed(blocks, source: source))
        let end = host.storage.length
        host.selection = NSRange(location: end, length: 0)
        layoutTables()
        applyTypingForCursor()
    }

    private var ns: NSString { host.storage.string as NSString }

    // MARK: Paragraphs

    /// The paragraph around `location`, newline included. Length 0 only for the empty last paragraph.
    func paragraph(at location: Int) -> NSRange {
        let length = ns.length
        let clamped = min(max(location, 0), length)
        if clamped == length, length == 0 || ns.character(at: length - 1) == 0x0A {
            return NSRange(location: length, length: 0)
        }
        return ns.paragraphRange(for: NSRange(location: clamped, length: 0))
    }

    func content(of paragraph: NSRange) -> NSRange {
        NoteDocument.content(of: paragraph, in: ns)
    }

    /// The style of a paragraph: the first character that carries one. UIKit does not always pass our own
    /// attributes on to typed text, so fresh characters may lack it. A last paragraph without any takes
    /// what the empty line had before it was typed into. See P-040.
    func style(of paragraph: NSRange) -> BlockStyle {
        guard paragraph.length > 0 else { return trailing }
        var found: BlockStyle?
        host.storage.enumerateAttribute(.inkhashBlockType, in: paragraph) { value, range, stop in
            if value != nil {
                found = BlockStyle(host.storage.attributes(at: range.location, effectiveRange: nil))
                stop.pointee = true
            }
        }
        if let found { return found }
        return NSMaxRange(paragraph) == ns.length && ns.character(at: ns.length - 1) != 0x0A ? trailing : .paragraph
    }

    private func paragraphs(in range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        var location = paragraph(at: range.location).location
        let end = NSMaxRange(range)
        while true {
            let current = paragraph(at: location)
            result.append(current)
            let next = NSMaxRange(current)
            if current.length == 0 || next > end || (range.length > 0 && next == end) { break }
            // The last paragraph without a newline: nothing follows it.
            if next >= ns.length, ns.length == 0 || ns.character(at: ns.length - 1) != 0x0A { break }
            location = next
        }
        return result
    }

    /// Rebuilds one paragraph with a new style, keeping its text and inline styles where the new type allows them.
    func setStyle(_ next: BlockStyle, of paragraph: NSRange) {
        if paragraph.length == 0 {
            trailing = next
            host.markers.trailing = next
            host.typing = NoteDocument.typingAttributes(next)
            publish()
            return
        }
        let old = style(of: paragraph)
        // An excerpt is one attachment; it has no text to restyle. See ADR 0032.
        if old.type == .excerpt, hasExcerpt(paragraph) { return }
        let contentRange = content(of: paragraph)
        var spans = RichText.spans(from: host.storage.attributedSubstring(from: contentRange), type: old.type)
        if old.type == .code {
            spans = spans.map { InlineSpan(text: $0.text) }
        }
        if next.type == .code {
            spans = [InlineSpan(text: spans.map(\.text).joined())]
        }
        if old.type == .tableRow, next.type != .tableRow {
            // Cells become words again.
            spans = spans.map { var span = $0; span.text = span.text.replacingOccurrences(of: "\t", with: "  "); return span }
        }
        if next.type == .tableRow, old.type != .tableRow, !spans.contains(where: { $0.text.contains("\t") }) {
            spans.append(InlineSpan(text: "\t"))
        }
        let rebuilt = NoteDocument.paragraph(spans, style: next, newline: paragraph.length > contentRange.length)
        let selection = host.selection
        edit(paragraph, replacement: rebuilt.string) {
            host.storage.replaceCharacters(in: paragraph, with: rebuilt)
        }
        host.selection = selection
        if next.type == .tableRow || old.type == .tableRow { layoutTable(around: paragraph.location) }
        applyTypingForCursor()
        publish()
    }

    // MARK: Delegate calls

    func shouldChange(_ range: NSRange, replacement text: String) -> Bool {
        if programmatic { return true }
        if text == "\n" {
            return newline(replacing: range)
        }
        if text.contains("\n") || text.contains("\r") || isExcerptLine(text) {
            insertMarkdown(text, replacing: range)
            return false
        }
        if !text.isEmpty, range.length == 0, insertBesideExcerpt(text, at: range.location) {
            return false
        }
        if text == " ", range.length == 0, applyShortcut(at: range.location) {
            return false
        }
        let rowStyle = style(of: paragraph(at: range.location))
        if rowStyle.type == .tableRow {
            // In a table `|` ends a cell, like in Markdown. Tab jumps to the next one. See ADR 0027.
            // Before an existing cell boundary `|` moves on instead of adding a column.
            if text == "|", range.length == 0, range.location < ns.length, ns.character(at: range.location) == 0x09 {
                nextCell()
                return false
            }
            if text == "|" {
                let tab = NSAttributedString(string: "\t", attributes: host.typing)
                edit(range, replacement: "\t") { host.storage.replaceCharacters(in: range, with: tab) }
                host.selection = NSRange(location: range.location + 1, length: 0)
                layoutTable(around: range.location)
                applyTypingForCursor()
                publish()
                return false
            }
            if text == "\t" {
                nextCell()
                return false
            }
        } else if text == "\t" {
            return false
        }
        pendingRange = NSRange(location: range.location, length: (text as NSString).length)
        return true
    }

    func didChange() {
        if programmatic { return }
        if let plan = pendingNewline {
            pendingNewline = nil
            finishNewline(plan)
            return
        }
        let changed = pendingRange ?? NSRange(location: 0, length: ns.length)
        pendingRange = nil
        if host.isComposing {
            publish()
            return
        }
        if reconcileInline() { return }
        restyle(changed)
        publish()
    }

    func selectionChanged() {
        if programmatic { return }
        applyTypingForCursor()
        updateState()
    }

    // MARK: Keys

    /// Return. Continues lists, ends them on an empty item, leaves headings for a paragraph.
    /// Returns true when the text view should insert the newline itself. Letting it do so keeps the
    /// keyboard's own idea of the text intact; an inserted newline behind its back scrambles autocorrect.
    private func newline(replacing range: NSRange) -> Bool {
        if slashOpen {
            session?.applySlash()
            return false
        }
        let current = paragraph(at: range.location)
        let currentStyle = style(of: current)
        let contentRange = content(of: current)
        if noteLinkOpen {
            session?.applyNoteLink()
            return false
        }
        if currentStyle.type == .tableRow {
            tableNewline(current)
            return false
        }
        if currentStyle.type == .paragraph, range.length == 0, startTable(current) {
            return false
        }
        if range.length == 0, contentRange.length == 0, currentStyle.hasMarker || currentStyle.type == .code {
            setStyle(.paragraph, of: current)
            return false
        }
        let atStart = range.location == current.location && contentRange.length > 0 && range.length == 0
        let upper: BlockStyle
        let below: BlockStyle
        if atStart {
            // A new empty line above; the paragraph keeps its type.
            upper = currentStyle.type == .code ? currentStyle : .paragraph
            below = currentStyle
        } else {
            upper = currentStyle
            switch currentStyle.type {
            case .bullet, .numbered, .code: below = BlockStyle(type: currentStyle.type, language: currentStyle.language)
            case .checkbox: below = BlockStyle(type: .checkbox)
            default: below = .paragraph
            }
        }
        pendingNewline = (range.location, atStart, upper, below)
        return true
    }

    /// Return from a key command. Text inserted from code skips `shouldChange`, so the rules run here. See P-029.
    func returnKey(insert: () -> Void) {
        guard newline(replacing: host.selection) else { return }
        insert()
        if let plan = pendingNewline {
            pendingNewline = nil
            finishNewline(plan)
        }
    }

    private func finishNewline(_ plan: (location: Int, atStart: Bool, upper: BlockStyle, below: BlockStyle)) {
        let cursor = host.selection
        let upperParagraph = paragraph(at: plan.location)
        let lowerParagraph = paragraph(at: plan.location + 1)
        if plan.atStart {
            setStyle(plan.upper, of: upperParagraph)
            setStyle(plan.below, of: paragraph(at: plan.location + 1))
        } else {
            setStyle(plan.below, of: lowerParagraph)
            setStyle(plan.upper, of: paragraph(at: plan.location))
        }
        host.selection = cursor
        applyTypingForCursor()
        publish()
    }

    /// Backspace at the start of a typed paragraph turns it into plain text first. Returns false to let the text view delete.
    func backspaceAtStart() -> Bool {
        let selection = host.selection
        guard selection.length == 0 else { return false }
        let current = paragraph(at: selection.location)
        guard selection.location == current.location else { return false }
        let currentStyle = style(of: current)
        guard currentStyle.type != .paragraph else { return false }
        if currentStyle.type == .excerpt, hasExcerpt(current) {
            // Never merge an excerpt into the paragraph above: go there, or drop it if it is empty.
            guard current.location > 0 else { return true }
            let above = paragraph(at: current.location - 1)
            if content(of: above).length == 0 {
                edit(above, replacement: "") { host.storage.deleteCharacters(in: above) }
                host.selection = NSRange(location: above.location, length: 0)
            } else {
                host.selection = NSRange(location: NSMaxRange(content(of: above)), length: 0)
            }
            applyTypingForCursor()
            publish()
            return true
        }
        setStyle(.paragraph, of: current)
        return true
    }

    // MARK: Commands from the sheet

    func setType(_ type: BlockType) {
        let selection = host.selection
        for paragraph in paragraphs(in: selection).reversed() where style(of: paragraph).type != type && !hasExcerpt(paragraph) {
            setStyle(BlockStyle(type: type), of: paragraph)
        }
        host.selection = selection
        host.focus()
        updateState()
    }

    func toggleChecked(_ paragraph: NSRange) {
        var next = style(of: paragraph)
        guard next.type == .checkbox else { return }
        next.checked.toggle()
        setStyle(next, of: paragraph)
    }

    func toggle(_ action: EditorAction) {
        let range = host.selection
        let current = InlineSelection.read(host.storage, range: range, typing: host.typing)
        if range.length == 0 {
            var typing = host.typing
            let font = (typing[.font] as? PlatformFont) ?? EditorFont.font(size: 18, bold: false, italic: false, code: false)
            switch action {
            case .toggleBold:
                typing[.font] = EditorFont.font(size: font.pointSize, bold: !current.bold, italic: current.italic, code: current.code)
            case .toggleItalic:
                typing[.font] = EditorFont.font(size: font.pointSize, bold: current.bold, italic: !current.italic, code: current.code)
            case .toggleCode:
                if current.code { typing.removeValue(forKey: .inkhashCode) } else { typing[.inkhashCode] = true }
                typing[.font] = EditorFont.font(size: font.pointSize, bold: false, italic: false, code: !current.code)
            case .setLink:
                break
            }
            host.typing = typing
            updateState()
            return
        }
        let storage = host.storage
        edit(range, replacement: nil) {
            switch action {
            case .toggleBold, .toggleItalic:
                storage.enumerateAttribute(.font, in: range) { value, run, _ in
                    let font = (value as? PlatformFont) ?? EditorFont.font(size: 18, bold: false, italic: false, code: false)
                    let italic = RichText.isItalic(font)
                    let bold = RichText.isBold(font)
                    let next = action == .toggleBold
                        ? EditorFont.font(size: font.pointSize, bold: !current.bold, italic: italic, code: false)
                        : EditorFont.font(size: font.pointSize, bold: bold, italic: !current.italic, code: false)
                    storage.addAttribute(.font, value: next, range: run)
                }
            case .toggleCode:
                if current.code {
                    storage.removeAttribute(.inkhashCode, range: range)
                } else {
                    storage.addAttribute(.inkhashCode, value: true, range: range)
                }
            case .setLink(let target):
                for key in RichText.linkAttributeKeys { storage.removeAttribute(key, range: range) }
                if let target { storage.addAttributes(RichText.linkAttributes(target), range: range) }
            }
        }
        host.selection = range
        restyle(range)
        publish()
    }

    func setLink(_ target: String?) {
        toggle(.setLink(target))
        host.focus()
    }

    func applySlash(_ command: SlashCommand) {
        guard let token = slashRange, NSMaxRange(token) <= ns.length else { return }
        let current = paragraph(at: token.location)
        edit(token, replacement: "") { host.storage.deleteCharacters(in: token) }
        host.selection = NSRange(location: token.location, length: 0)
        slashRange = nil
        suppressedSlash = nil
        if let type = command.blockType {
            setStyle(BlockStyle(type: type), of: paragraph(at: current.location))
        } else {
            applyTypingForCursor()
            publish()
            if let action = command.inlineAction { toggle(action) }
        }
    }

    func escapeSlash() {
        if let token = slashRange { suppressedSlash = Self.key(token, ns.substring(with: token)) }
        updateState()
    }

    private static func key(_ token: NSRange, _ text: String) -> String {
        "\(token.location):\(text)"
    }

    /// `/query` right before the cursor. The slash starts the paragraph or follows a space, so `und/oder`
    /// and addresses stay text. See ADR 0033.
    private func slashToken(at cursor: Int, in contentRange: NSRange) -> NSRange? {
        var start = cursor
        while start > contentRange.location {
            let unit = ns.character(at: start - 1)
            if unit == 0x2F { // `/`
                let before = start - 1
                guard before == contentRange.location || Self.isSpace(ns.character(at: before - 1)) else { return nil }
                return NSRange(location: before, length: cursor - before)
            }
            if Self.isSpace(unit) { return nil }
            start -= 1
        }
        return nil
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0xA0
    }

    func focus() {
        host.focus()
        updateState()
    }

    func focusEnd() {
        host.selection = NSRange(location: ns.length, length: 0)
        host.focus()
        applyTypingForCursor()
        updateState()
    }

    /// The checkbox paragraph whose marker lies under `point` (text view coordinates), if any.
    func checkbox(at point: CGPoint) -> NSRange? {
        let local = CGPoint(x: point.x - host.containerOrigin.x, y: point.y - host.containerOrigin.y)
        guard local.x >= 0, local.x < NoteDocument.gutter else { return nil }
        let layout = host.markers
        layout.ensureLayout(for: host.container)
        let extra = layout.extraLineFragmentRect
        if extra.height > 0, local.y >= extra.minY, local.y <= extra.maxY {
            return trailing.type == .checkbox ? NSRange(location: ns.length, length: 0) : nil
        }
        guard ns.length > 0 else { return nil }
        let glyph = layout.glyphIndex(for: CGPoint(x: NoteDocument.gutter, y: local.y), in: host.container)
        let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        guard local.y >= fragment.minY, local.y <= fragment.maxY else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        let found = paragraph(at: character)
        guard style(of: found).type == .checkbox else { return nil }
        // Only the first line of a paragraph carries its marker.
        let first = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: found.location), effectiveRange: nil)
        return first.minY == fragment.minY ? found : nil
    }

    /// Height of the text at `width`. Never resizes the live container, see P-037.
    func height(for width: CGFloat) -> CGFloat {
        if abs(width - tableWidth) > 0.5, hasTables {
            // Not during SwiftUI's measuring pass: changing the text there re-enters layout.
            DispatchQueue.main.async { [weak self] in self?.layoutTables(width: width) }
        }
        let layout = host.markers
        let container = host.container
        let used: CGFloat
        // The live layout only counts if its container is as wide as asked and not capped in height.
        // UIKit sets a non-scrolling text view's container to the view's own height, see P-037.
        if abs(container.size.width - width) < 0.5, container.size.height > 100_000 {
            layout.ensureLayout(for: container)
            used = layout.usedRect(for: container).height
        } else {
            let storage = NSTextStorage(attributedString: host.storage)
            let scratchLayout = NSLayoutManager()
            let scratch = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            scratch.lineFragmentPadding = 0
            scratchLayout.addTextContainer(scratch)
            storage.addLayoutManager(scratchLayout)
            scratchLayout.ensureLayout(for: scratch)
            used = scratchLayout.usedRect(for: scratch).height
        }
        return ceil(max(used, 24)) + host.containerOrigin.y * 2 + 4
    }

    // MARK: Excerpts

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
    private func isExcerptLine(_ text: String) -> Bool {
        let blocks = MarkdownCodec.parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return blocks.count == 1 && MarkdownCodec.excerpt(in: blocks[0]) != nil
    }

    /// Text typed into an excerpt's paragraph goes into a new paragraph before or after it.
    private func insertBesideExcerpt(_ text: String, at location: Int) -> Bool {
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

    // MARK: Internals

    private func edit(_ range: NSRange, replacement: String?, _ body: () -> Void) {
        programmatic = true
        host.performEdit(range, replacement: replacement, body)
        programmatic = false
    }

    /// Block shortcut on space at the start of a plain paragraph: `#`, `-`, `[ ]`, `1.`, ```` ``` ````.
    private func applyShortcut(at location: Int) -> Bool {
        let current = paragraph(at: location)
        guard style(of: current).type == .paragraph, location > current.location else { return false }
        let token = ns.substring(with: NSRange(location: current.location, length: location - current.location))
        guard let type = BlockShortcut.type(forToken: token) else { return false }
        let tokenRange = NSRange(location: current.location, length: location - current.location)
        // Clear the marker in the same call, so fast typing cannot land behind it. See P-028.
        edit(tokenRange, replacement: "") { host.storage.deleteCharacters(in: tokenRange) }
        host.selection = NSRange(location: current.location, length: 0)
        setStyle(BlockStyle(type: type), of: paragraph(at: current.location))
        host.selection = NSRange(location: current.location, length: 0)
        applyTypingForCursor()
        return true
    }

    /// Pasted or dictated text with line breaks is read as Markdown.
    private func insertMarkdown(_ text: String, replacing range: NSRange) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = MarkdownCodec.parse(normalized)
        let inserted: NSAttributedString
        if blocks.count == 1, blocks[0].type == .paragraph {
            let style = self.style(of: paragraph(at: range.location))
            inserted = NoteDocument.paragraph(blocks[0].spans, style: style, newline: false)
        } else if blocks.contains(where: { $0.type == .excerpt }) {
            // An excerpt stands in its own paragraph: break the line before and after it where needed.
            let built = NSMutableAttributedString(attributedString: NoteDocument.attributed(blocks, source: source))
            let current = paragraph(at: range.location)
            let contentRange = content(of: current)
            if range.location > contentRange.location {
                built.insert(NSAttributedString(string: "\n", attributes: host.typing), at: 0)
            }
            if NSMaxRange(range) < NSMaxRange(contentRange) {
                built.append(NSAttributedString(string: "\n", attributes: NoteDocument.typingAttributes(.paragraph)))
            }
            inserted = built
        } else {
            inserted = NoteDocument.attributed(blocks, source: source)
        }
        edit(range, replacement: inserted.string) { host.storage.replaceCharacters(in: range, with: inserted) }
        host.selection = NSRange(location: range.location + inserted.length, length: 0)
        restyle(NSRange(location: range.location, length: inserted.length))
        applyTypingForCursor()
        publish()
    }

    /// Turns closed `**x**`, `*x*`, `` `x` `` and `[x](y)` in the cursor's paragraph into styles.
    private func reconcileInline() -> Bool {
        let cursor = host.selection.location
        let current = paragraph(at: cursor)
        guard current.length > 0 else { return false }
        let currentStyle = style(of: current)
        guard currentStyle.type != .code, currentStyle.type != .excerpt else { return false }
        let contentRange = content(of: current)
        let text = host.storage.attributedSubstring(from: contentRange)
        guard let rewritten = RichText.reconcile(text, cursor: cursor - contentRange.location, type: currentStyle.type) else { return false }
        let rebuilt = NoteDocument.paragraph(rewritten.spans, style: currentStyle, newline: false)
        edit(contentRange, replacement: rebuilt.string) { host.storage.replaceCharacters(in: contentRange, with: rebuilt) }
        host.selection = NSRange(location: contentRange.location + rewritten.cursor, length: 0)
        // A closed marker ends the style: what comes next is plain.
        host.typing = NoteDocument.typingAttributes(currentStyle)
        publish()
        return true
    }

    /// Gives each touched paragraph the style of its first character and fonts that fit it.
    private func restyle(_ range: NSRange) {
        let storage = host.storage
        guard storage.length > 0 else { return }
        storage.beginEditing()
        for current in paragraphs(in: range) where current.length > 0 {
            var currentStyle = style(of: current)
            // An excerpt whose attachment was deleted is an ordinary line again.
            if currentStyle.type == .excerpt, !hasExcerpt(current) { currentStyle = .paragraph }
            let heading = RichText.isHeading(currentStyle.type)
            let size = EditorFont.size(for: currentStyle.type)
            storage.addAttributes(currentStyle.attributes, range: current)
            if currentStyle.type == .code {
                storage.addAttribute(.inkhashCode, value: true, range: current)
            }
            storage.enumerateAttributes(in: current) { attributes, run, _ in
                let font = attributes[.font] as? PlatformFont
                let code = attributes[.inkhashCode] != nil
                let bold = heading || (font.map(RichText.isBold) ?? false)
                let italic = font.map(RichText.isItalic) ?? false
                storage.addAttribute(.font, value: EditorFont.font(size: size, bold: bold && !code, italic: italic && !code, code: code), range: run)
            }
            RichText.highlightMarkers(in: storage, range: content(of: current), type: currentStyle.type)
        }
        storage.endEditing()
        for current in paragraphs(in: range) where current.length > 0 && style(of: current).type == .tableRow {
            layoutTable(around: current.location)
        }
    }

    // MARK: Tables

    private var hasTables: Bool {
        var found = false
        host.storage.enumerateAttribute(.inkhashBlockType, in: NSRange(location: 0, length: host.storage.length)) { value, _, stop in
            if value as? String == BlockType.tableRow.rawValue { found = true; stop.pointee = true }
        }
        return found
    }

    /// The rows of the table that contains `location`.
    private func tableRows(around location: Int) -> [NSRange] {
        let start = paragraph(at: location)
        guard style(of: start).type == .tableRow, start.length > 0 else { return [] }
        var rows = [start]
        var cursor = start.location
        while cursor > 0 {
            let previous = paragraph(at: cursor - 1)
            guard style(of: previous).type == .tableRow else { break }
            rows.insert(previous, at: 0)
            cursor = previous.location
        }
        var next = NSMaxRange(start)
        while next < ns.length {
            let following = paragraph(at: next)
            guard following.length > 0, style(of: following).type == .tableRow else { break }
            rows.append(following)
            next = NSMaxRange(following)
        }
        return rows
    }

    /// The style of the table these rows form, kept on its first row.
    private func tableStyle(_ rows: [NSRange]) -> TableFormat? {
        guard let first = rows.first, first.length > 0 else { return nil }
        return (host.storage.attribute(.inkhashTable, at: first.location, effectiveRange: nil) as? TableFormatBox)?.style
    }

    /// The table and column the cursor is in, for the table menu. See ADR 0036.
    var tableAtCursor: (style: TableFormat, column: Int, columns: Int)? {
        let cursor = host.selection.location
        let row = paragraph(at: cursor)
        guard row.length > 0, style(of: row).type == .tableRow else { return nil }
        let rows = tableRows(around: cursor)
        let before = ns.substring(with: NSRange(location: row.location, length: max(0, cursor - row.location)))
        let column = before.filter { $0 == "\t" }.count
        return (tableStyle(rows) ?? .plain, column, max(1, rows.map(cellCount).max() ?? 1))
    }

    /// Changes the style of the table at the cursor and lays it out again.
    func changeTable(_ change: (inout TableFormat, _ column: Int, _ columns: Int) -> Void) {
        guard let current = tableAtCursor else { return }
        var next = current.style
        change(&next, current.column, current.columns)
        let rows = tableRows(around: host.selection.location)
        guard let first = rows.first, next != current.style else { return }
        let selection = host.selection
        programmatic = true
        host.storage.beginEditing()
        host.storage.removeAttribute(.inkhashTable, range: first)
        if next != .plain { host.storage.addAttribute(.inkhashTable, value: TableFormatBox(next), range: first) }
        host.storage.endEditing()
        programmatic = false
        host.selection = selection
        layoutTable(around: first.location)
        publish()
        updateState()
    }

    private func cellCount(_ row: NSRange) -> Int {
        ns.substring(with: content(of: row)).components(separatedBy: "\t").count
    }

    /// Equal columns across the text width, as tab stops. The layout manager draws the grid on them.
    private func layoutTable(around location: Int, width: CGFloat? = nil) {
        let rows = tableRows(around: location)
        guard !rows.isEmpty else { return }
        let columns = max(1, rows.map(cellCount).max() ?? 1)
        let total = max((width ?? host.container.size.width) - NoteDocument.gutter, 120)
        let table = tableStyle(rows) ?? .plain
        let edges = NoteDocument.tableEdges(columns: columns, width: total, table: table)
        let style = NoteDocument.tableStyle(edges: edges, table: table, header: false)
        let header = NoteDocument.tableStyle(edges: edges, table: table, header: true)
        programmatic = true
        host.storage.beginEditing()
        for (index, row) in rows.enumerated() {
            host.storage.addAttribute(.paragraphStyle, value: index == 0 ? header : style, range: row)
            host.storage.addAttribute(.inkhashTableColumns, value: columns, range: row)
            let layout = TableRowLayout(edges: edges, index: index, header: table.header, zebra: table.zebra, last: index == rows.count - 1)
            host.storage.addAttribute(.inkhashTableRow, value: layout, range: row)
            // The header reads as a label row: muted, not louder.
            let isHeader = index == 0 && table.header
            host.storage.enumerateAttribute(.inkhashLink, in: content(of: row)) { link, run, _ in
                guard link == nil else { return }
                host.storage.addAttribute(.foregroundColor, value: isHeader ? RichText.mutedColor : RichText.inkColor, range: run)
            }
        }
        host.storage.endEditing()
        programmatic = false
    }

    private func layoutTables(width: CGFloat? = nil) {
        tableWidth = width ?? host.container.size.width
        var location = 0
        while location < ns.length {
            let current = paragraph(at: location)
            if current.length == 0 { break }
            if style(of: current).type == .tableRow {
                let rows = tableRows(around: current.location)
                layoutTable(around: current.location, width: width)
                location = NSMaxRange(rows.last ?? current)
            } else {
                location = NSMaxRange(current)
            }
        }
        host.contentChanged()
    }

    /// Tab in a table: behind the next tab of the row, else the start of the next row, else a new row.
    private func nextCell() {
        let cursor = host.selection.location
        let row = paragraph(at: cursor)
        let rowContent = content(of: row)
        let rest = NSRange(location: cursor, length: NSMaxRange(rowContent) - cursor)
        let tab = ns.range(of: "\t", options: [], range: rest)
        if tab.location != NSNotFound {
            host.selection = NSRange(location: tab.location + 1, length: 0)
        } else if NSMaxRange(row) < ns.length, style(of: paragraph(at: NSMaxRange(row))).type == .tableRow {
            host.selection = NSRange(location: NSMaxRange(row), length: 0)
        } else {
            tableNewline(row, atEnd: true)
            return
        }
        applyTypingForCursor()
        updateState()
    }

    /// Return in a table adds a row below with as many cells. On an empty row it leaves the table.
    private func tableNewline(_ row: NSRange, atEnd: Bool = false) {
        let text = ns.substring(with: content(of: row))
        if text.trimmingCharacters(in: CharacterSet(charactersIn: "\t ")).isEmpty, !atEnd {
            let rows = tableRows(around: row.location)
            if rows.count > 1 {
                let contentRange = content(of: row)
                edit(contentRange, replacement: "") { host.storage.deleteCharacters(in: contentRange) }
                setStyle(.paragraph, of: paragraph(at: row.location))
                host.selection = NSRange(location: row.location, length: 0)
                applyTypingForCursor()
                publish()
                return
            }
        }
        let columns = max(1, tableRows(around: row.location).map(cellCount).max() ?? cellCount(row))
        let style = BlockStyle(type: .tableRow)
        let empty = String(repeating: "\t", count: columns - 1)
        let insertAt = NSMaxRange(content(of: row))
        let inserted = NoteDocument.paragraph([InlineSpan(text: empty)], style: style, newline: false)
        let piece = NSMutableAttributedString(string: "\n", attributes: NoteDocument.typingAttributes(style))
        piece.append(inserted)
        let at = NSRange(location: insertAt, length: 0)
        edit(at, replacement: piece.string) { host.storage.replaceCharacters(in: at, with: piece) }
        host.selection = NSRange(location: insertAt + 1, length: 0)
        layoutTable(around: insertAt + 1)
        applyTypingForCursor()
        publish()
    }

    /// `| a | b |` and Return turns the line into the header of a new table. See ADR 0027.
    private func startTable(_ current: NSRange) -> Bool {
        let line = ns.substring(with: content(of: current)).trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("|"), line.filter({ $0 == "|" }).count >= 2 else { return false }
        var inner = line.dropFirst()
        if inner.hasSuffix("|") { inner = inner.dropLast() }
        let cells = inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !cells.isEmpty else { return false }
        let style = BlockStyle(type: .tableRow)
        let header = NoteDocument.paragraph(
            MarkdownCodec.parseInline(cells.joined(separator: "\t")).spans, style: style, newline: false
        )
        let contentRange = content(of: current)
        edit(contentRange, replacement: header.string) { host.storage.replaceCharacters(in: contentRange, with: header) }
        tableNewline(paragraph(at: current.location), atEnd: true)
        return true
    }

    /// Typing attributes follow the paragraph the cursor is in, not the character before it.
    private func applyTypingForCursor() {
        let selection = host.selection
        guard selection.length == 0 else { return }
        let current = paragraph(at: selection.location)
        let currentStyle = style(of: current)
        let contentRange = content(of: current)
        var typing: [NSAttributedString.Key: Any]
        if selection.location > contentRange.location, selection.location - 1 < host.storage.length {
            typing = host.storage.attributes(at: selection.location - 1, effectiveRange: nil)
        } else if contentRange.length > 0 {
            typing = host.storage.attributes(at: contentRange.location, effectiveRange: nil)
        } else {
            typing = NoteDocument.typingAttributes(currentStyle)
        }
        // A link ends where it ends; typing after it is plain.
        if selection.location == NSMaxRange(contentRange) || selection.location == contentRange.location {
            for key in RichText.linkAttributeKeys { typing.removeValue(forKey: key) }
            typing[.foregroundColor] = RichText.inkColor
        }
        typing.removeValue(forKey: .attachment)
        let typingStyle = currentStyle.type == .excerpt ? BlockStyle.paragraph : currentStyle
        typing.merge(typingStyle.attributes) { _, new in new }
        host.typing = typing
    }

    private func publish() {
        let length = ns.length
        if length > 0, ns.character(at: length - 1) != 0x0A, trailing != .paragraph {
            trailing = .paragraph
            host.markers.trailing = trailing
        }
        session?.commit(NoteDocument.blocks(from: host.storage, trailing: trailing))
        host.contentChanged()
        updateState()
    }

    func updateState() {
        let selection = host.selection
        let current = paragraph(at: selection.location)
        let currentStyle = style(of: current)
        let contentRange = content(of: current)
        var query: String?
        var token: NSRange?
        if selection.length == 0, currentStyle.type != .code, currentStyle.type != .excerpt {
            token = slashToken(at: selection.location, in: contentRange)
        }
        let tokenKey = token.map { Self.key($0, ns.substring(with: $0)) }
        if suppressedSlash != nil, tokenKey != suppressedSlash { suppressedSlash = nil }
        if let token, tokenKey != suppressedSlash {
            query = String(ns.substring(with: token).dropFirst())
            slashRange = token
        } else {
            slashRange = nil
        }
        slashOpen = query != nil
        let noteQuery = selection.length == 0 ? openNoteQuery(before: selection.location, in: contentRange) : nil
        noteLinkOpen = noteQuery != nil
        session?.update(EditorState(
            selection: InlineSelection.read(host.storage, range: selection, typing: host.typing),
            blockType: currentStyle.type,
            slashQuery: query,
            slashInline: slashRange.map { $0.location > contentRange.location } ?? false,
            slashLineEmpty: slashRange.map { $0.length == contentRange.length } ?? false,
            caret: caretRect(selection.location),
            selectionRect: selection.length > 0 ? firstLineRect(selection) : nil,
            noteQuery: noteQuery,
            caretLink: selection.length == 0 ? link(around: selection.location) : nil,
            table: tableAtCursor?.style,
            tableColumn: tableAtCursor?.column ?? 0,
            tableColumns: tableAtCursor?.columns ?? 0
        ))
    }

    // MARK: Note links

    var isInTable: Bool {
        style(of: paragraph(at: host.selection.location)).type == .tableRow
    }

    /// The link whose text the cursor touches, on either side.
    private func link(around location: Int) -> String? {
        for index in [location, location - 1] where index >= 0 && index < host.storage.length {
            if let target = host.storage.attribute(.inkhashLink, at: index, effectiveRange: nil) as? String { return target }
        }
        return nil
    }

    /// `[[abc` right before the cursor, without a closing bracket or a line break: "abc".
    private func openNoteQuery(before location: Int, in contentRange: NSRange) -> String? {
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

    private func caretRect(_ location: Int) -> CGRect {
        let layout = host.markers
        layout.ensureLayout(for: host.container)
        let origin = host.containerOrigin
        let rect: CGRect
        if paragraph(at: location).length == 0 || ns.length == 0 {
            rect = layout.extraLineFragmentRect
        } else {
            let glyph = layout.glyphIndexForCharacter(at: min(location, ns.length - 1))
            rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        }
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    private func firstLineRect(_ range: NSRange) -> CGRect {
        let layout = host.markers
        layout.ensureLayout(for: host.container)
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return caretRect(range.location) }
        var line = NSRange()
        layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &line)
        let first = NSIntersectionRange(glyphs, line)
        let rect = layout.boundingRect(forGlyphRange: first.length > 0 ? first : glyphs, in: host.container)
        return rect.offsetBy(dx: host.containerOrigin.x, dy: host.containerOrigin.y)
    }
}
