import InkhashCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What a paragraph is. Lives on every character of the paragraph, newline included. See ADR 0025.
struct BlockStyle: Equatable {
    var type: BlockType
    var checked = false
    var language = ""
    /// Only on the first row of a styled table. See ADR 0036.
    var table: TableFormat?
    /// Level of a nested list item, 0 for everything else. See ADR 0086.
    var indent = 0

    static let paragraph = BlockStyle(type: .paragraph)

    init(type: BlockType, checked: Bool = false, language: String = "", table: TableFormat? = nil, indent: Int = 0) {
        self.type = type
        self.checked = checked
        self.language = language
        self.table = table
        self.indent = Block.isListItem(type) ? min(max(indent, 0), Block.maxIndent) : 0
    }

    init(_ attributes: [NSAttributedString.Key: Any]) {
        type = (attributes[.inkhashBlockType] as? String).flatMap(BlockType.init(rawValue:)) ?? .paragraph
        checked = attributes[.inkhashChecked] as? Bool ?? false
        language = attributes[.inkhashLanguage] as? String ?? ""
        table = type == .tableRow ? (attributes[.inkhashTable] as? TableFormatBox)?.style : nil
        indent = Block.isListItem(type) ? attributes[.inkhashIndent] as? Int ?? 0 : 0
    }

    init(_ block: Block) {
        self.init(type: block.type, checked: block.checked, language: block.language, table: block.table, indent: block.indent)
    }

    var attributes: [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [
            .inkhashBlockType: type.rawValue,
            .inkhashChecked: checked,
            .inkhashLanguage: language,
            .inkhashIndent: indent,
            .paragraphStyle: NoteDocument.paragraphStyle(type, indent: indent),
        ]
        if let table { result[.inkhashTable] = TableFormatBox(table) }
        return result
    }

    var hasMarker: Bool { Block.isListItem(type) }

    /// The same item one level deeper or shallower, within the bounds.
    func indented(by step: Int) -> BlockStyle {
        BlockStyle(type: type, checked: checked, language: language, table: table, indent: indent + step)
    }
}

/// Converts between the blocks of a note and the one attributed text the editor shows. See ADR 0025.
enum NoteDocument {
    /// Left indent of every paragraph. Markers are drawn inside it; title and path start at it.
    static let gutter: CGFloat = 38
    /// Space between a marker and the text.
    static let markerGap: CGFloat = 10

    /// How far the text of a list item stands right of the paragraphs: its marker sits in between,
    /// where paragraphs begin. Zero for everything else. See ADR 0062.
    static func listIndent(_ type: BlockType) -> CGFloat {
        switch type {
        case .bullet, .numbered: EditorFont.scaled(24)
        case .checkbox: EditorFont.scaled(28)
        default: 0
        }
    }

    /// How far one level of a nested list item moves right: its marker then stands under the parent's text.
    static func levelOffset(_ indent: Int) -> CGFloat {
        CGFloat(indent) * EditorFont.scaled(24)
    }

    static func paragraphStyle(_ type: BlockType, indent: Int = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = gutter + levelOffset(indent) + listIndent(type)
        style.headIndent = gutter + levelOffset(indent) + listIndent(type)
        style.lineSpacing = EditorFont.lineSpacing(for: type)
        style.paragraphSpacingBefore = EditorFont.scaled(spacingBefore(type))
        return style
    }

    /// Space above a paragraph at the default text size. List items stay close to each other;
    /// the line spacing of the paragraph before adds to it.
    private static func spacingBefore(_ type: BlockType) -> CGFloat {
        switch type {
        case .heading1: return 28
        case .heading2: return 22
        case .heading3: return 16
        case .bullet, .numbered, .checkbox: return 4
        case .code: return 2
        default: return 10
        }
    }

    /// Inner margin of a table cell.
    static let cellPadding: CGFloat = 8

    /// A table row: equal columns over `width`, which starts at the gutter. See ADR 0027.
    /// Column boundaries from the text's left edge for a table of `total` width.
    static func tableEdges(columns: Int, width total: CGFloat, table: TableFormat) -> [CGFloat] {
        var edges: [CGFloat] = [0]
        for share in table.shares(columns: columns) {
            edges.append((edges.last ?? 0) + CGFloat(share) * total)
        }
        return edges
    }

    /// A table row: columns at `edges`, each cell aligned by the table's style. The first cell is
    /// always left; alignment needs a tab in front of the text. See ADR 0036.
    static func tableStyle(edges: [CGFloat], table: TableFormat, header: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let columns = max(edges.count - 1, 1)
        style.firstLineHeadIndent = gutter + cellPadding
        style.headIndent = gutter + cellPadding
        style.tailIndent = -cellPadding
        style.tabStops = (1..<max(columns, 1)).map { column in
            let left = edges[column], right = edges[column + 1]
            switch table.alignment(of: column) {
            case .left: return NSTextTab(textAlignment: .left, location: gutter + left + cellPadding)
            case .center: return NSTextTab(textAlignment: .center, location: gutter + (left + right) / 2)
            case .right: return NSTextTab(textAlignment: .right, location: gutter + right - cellPadding)
            }
        }
        style.defaultTabInterval = (edges.last ?? 0) / CGFloat(columns)
        style.paragraphSpacingBefore = header ? EditorFont.scaled(10) : 0
        style.paragraphSpacing = 0
        style.lineSpacing = 2
        style.lineHeightMultiple = 1.25
        return style
    }

    /// Typing attributes for an empty paragraph of this style.
    static func typingAttributes(_ style: BlockStyle) -> [NSAttributedString.Key: Any] {
        RichText.typingAttributes(for: style.type).merging(style.attributes) { _, new in new }
    }

    /// One paragraph: its spans styled for the type, the block attributes on all of it, and a newline if asked.
    static func paragraph(_ spans: [InlineSpan], style: BlockStyle, newline: Bool) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: RichText.attributed(spans, type: style.type))
        if newline {
            text.append(NSAttributedString(string: "\n", attributes: typingAttributes(style)))
        }
        let full = NSRange(location: 0, length: text.length)
        if full.length > 0 {
            text.addAttributes(style.attributes, range: full)
            RichText.highlightMarkers(in: text, range: full, type: style.type)
            let content = newline ? NSRange(location: 0, length: full.length - 1) : full
            RichText.decorateTask(in: text, range: content, style: style)
        }
        return text
    }

    /// An excerpt: one attachment character that draws the page rectangle. See ADR 0032.
    @MainActor
    static func excerptParagraph(_ target: ExcerptTarget, label: String, source: ExcerptSource, newline: Bool) -> NSAttributedString {
        let style = BlockStyle(type: .excerpt)
        let attachment = ExcerptAttachment(target: target, label: label, source: source)
        let text = NSMutableAttributedString(attachment: attachment)
        if newline { text.append(NSAttributedString(string: "\n")) }
        text.addAttributes(typingAttributes(style), range: NSRange(location: 0, length: text.length))
        return text
    }

    /// The whole note. A code block becomes one paragraph per line, an excerpt one attachment.
    @MainActor
    static func attributed(_ blocks: [Block], source: ExcerptSource) -> NSAttributedString {
        var lines: [([InlineSpan], BlockStyle)] = []
        var excerpts: [Int: (ExcerptTarget, String)] = [:]
        for block in blocks {
            let style = BlockStyle(block)
            if let excerpt = MarkdownCodec.excerpt(in: block) {
                excerpts[lines.count] = (excerpt, block.plain)
                lines.append(([], style))
            } else if block.type == .excerpt {
                lines.append((block.spans, .paragraph))
            } else if block.type == .code {
                for line in block.plain.components(separatedBy: "\n") {
                    lines.append(([InlineSpan(text: line)], style))
                }
            } else {
                lines.append((block.spans, style))
            }
        }
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let newline = index < lines.count - 1
            if let (excerpt, label) = excerpts[index] {
                result.append(excerptParagraph(excerpt, label: label, source: source, newline: newline))
                continue
            }
            result.append(paragraph(line.0, style: line.1, newline: newline))
        }
        return result
    }

    /// Style of the paragraph that ends the text without a character of its own, if any.
    static func trailingStyle(of blocks: [Block]) -> BlockStyle {
        guard let last = blocks.last, last.plain.isEmpty else { return .paragraph }
        return BlockStyle(last)
    }

    /// Back to blocks. `trailing` is the style of an empty last paragraph, which has no character to carry it.
    static func blocks(from text: NSAttributedString, trailing: BlockStyle) -> [Block] {
        let ns = text.string as NSString
        var blocks: [Block] = []
        var previousWasCode = false

        func add(_ content: NSRange, style: BlockStyle) {
            if style.type == .code {
                let line = ns.substring(with: content)
                if previousWasCode, let last = blocks.last {
                    blocks[blocks.count - 1] = Block(
                        id: last.id, type: .code, spans: [InlineSpan(text: last.plain + "\n" + line)],
                        language: last.language
                    )
                } else {
                    blocks.append(Block(type: .code, spans: [InlineSpan(text: line)], language: style.language))
                }
                previousWasCode = true
                return
            }
            if style.type == .excerpt {
                addExcerpt(content)
                return
            }
            let spans = RichText.spans(from: text.attributedSubstring(from: content), type: style.type)
            blocks.append(Block(type: style.type, spans: spans, checked: style.checked, table: style.table, indent: style.indent))
            previousWasCode = false
        }

        /// The attachment becomes the excerpt block; anything typed beside it stays as its own paragraph.
        func addExcerpt(_ content: NSRange) {
            var rest = NSMutableAttributedString()
            text.enumerateAttribute(.attachment, in: content) { value, range, _ in
                if let attachment = value as? ExcerptAttachment {
                    if rest.length > 0 {
                        blocks.append(Block(type: .paragraph, spans: RichText.spans(from: rest, type: .paragraph)))
                        rest = NSMutableAttributedString()
                    }
                    blocks.append(MarkdownCodec.excerptBlock(attachment.target, label: attachment.label))
                } else {
                    let piece = text.attributedSubstring(from: range).string.replacingOccurrences(of: "\u{FFFC}", with: "")
                    if !piece.isEmpty { rest.append(text.attributedSubstring(from: range)) }
                }
            }
            if rest.length > 0, !rest.string.replacingOccurrences(of: "\u{FFFC}", with: "").isEmpty {
                blocks.append(Block(type: .paragraph, spans: RichText.spans(from: rest, type: .paragraph)))
            }
            previousWasCode = false
        }

        var location = 0
        while location < ns.length {
            let paragraph = ns.paragraphRange(for: NSRange(location: location, length: 0))
            let style = BlockStyle(text.attributes(at: paragraph.location, effectiveRange: nil))
            add(content(of: paragraph, in: ns), style: style)
            location = NSMaxRange(paragraph)
        }
        if ns.length == 0 || ns.character(at: ns.length - 1) == 0x0A {
            add(NSRange(location: ns.length, length: 0), style: trailing)
        }
        return blocks
    }

    /// A paragraph range without its newline.
    static func content(of paragraph: NSRange, in ns: NSString) -> NSRange {
        var range = paragraph
        if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == 0x0A {
            range.length -= 1
        }
        return range
    }
}

/// Draws list markers, checkboxes and the code background in the left indent. TextKit 1 only, see ADR 0025.
final class MarkerLayoutManager: NSLayoutManager {
    /// Style of the empty last paragraph, drawn in the extra line fragment.
    var trailing = BlockStyle.paragraph
    /// Where the open find bar matches, and the one it stands on. See ADR 0084.
    var findMatches: [NSRange] = []
    var findCurrent: NSRange?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        drawFindMatches(in: glyphsToShow, origin: origin)
        let ns = storage.string as NSString
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var cursor = chars.location < ns.length ? ns.paragraphRange(for: NSRange(location: chars.location, length: 0)).location : ns.length
        while cursor < ns.length, cursor <= NSMaxRange(chars) {
            let paragraph = ns.paragraphRange(for: NSRange(location: cursor, length: 0))
            let style = BlockStyle(storage.attributes(at: paragraph.location, effectiveRange: nil))
            if style.type == .code {
                drawCodeBackground(paragraph, origin: origin)
            } else if style.type == .tableRow {
                drawTableRow(paragraph, in: storage, origin: origin)
            } else if style.hasMarker {
                let glyph = glyphIndexForCharacter(at: paragraph.location)
                let fragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let baseline = fragment.minY + location(forGlyphAt: glyph).y
                drawMarker(style, number: number(endingAt: paragraph.location, in: storage), baseline: baseline, origin: origin)
                if style.type == .checkbox { drawDueDays(in: paragraph, storage: storage, checked: style.checked, origin: origin) }
            }
            cursor = NSMaxRange(paragraph)
        }
        let atEnd = NSMaxRange(glyphsToShow) >= numberOfGlyphs
        let fragment = extraLineFragmentRect
        if atEnd, trailing.hasMarker, fragment.height > 0 {
            let font = EditorFont.font(for: trailing.type, bold: false, italic: false, code: false)
            let baseline = fragment.maxY - abs(font.descender) - EditorFont.lineSpacing(for: trailing.type)
            drawMarker(trailing, number: number(endingAt: ns.length, in: storage), baseline: baseline, origin: origin)
        }
    }

    /// 1 for the first of a run of numbered paragraphs at one level; deeper items in between do not end the run.
    /// Matches how the codec numbers them (ADR 0086).
    private func number(endingAt location: Int, in storage: NSTextStorage) -> Int {
        let ns = storage.string as NSString
        let level = location < ns.length
            ? BlockStyle(storage.attributes(at: ns.paragraphRange(for: NSRange(location: location, length: 0)).location, effectiveRange: nil)).indent
            : trailing.indent
        var count = 1
        var cursor = location
        while cursor > 0 {
            let previous = ns.paragraphRange(for: NSRange(location: cursor - 1, length: 0))
            let style = BlockStyle(storage.attributes(at: previous.location, effectiveRange: nil))
            guard style.hasMarker, style.indent >= level else { break }
            if style.indent == level {
                guard style.type == .numbered else { break }
                count += 1
            }
            cursor = previous.location
        }
        return count
    }

    /// Markers stand where paragraphs begin; the item's text starts one step right of them. See ADR 0062.
    private func drawMarker(_ style: BlockStyle, number: Int, baseline: CGFloat, origin: CGPoint) {
        let size = EditorFont.size(for: style.type)
        let start = origin.x + NoteDocument.gutter + NoteDocument.levelOffset(style.indent)
        let text = start + NoteDocument.listIndent(style.type)
        let y = origin.y + baseline
        switch style.type {
        case .bullet:
            draw("•", font: EditorFont.font(for: style.type, bold: false, italic: false, code: false), color: RichText.inkColor, right: text - EditorFont.scaled(12), baseline: y)
        case .numbered:
            draw("\(number).", font: EditorFont.font(size: size * 0.85, serif: false, bold: false, italic: false, code: false), color: Self.mutedColor, right: text - EditorFont.scaled(7), baseline: y)
        case .checkbox:
            let side = EditorFont.scaled(18)
            let font = EditorFont.font(for: style.type, bold: false, italic: false, code: false)
            let rect = CGRect(x: start, y: y - font.xHeight / 2 - side / 2, width: side, height: side)
            drawCheckbox(checked: style.checked, in: rect)
        default:
            break
        }
    }

    /// The glyphs of a due day are not drawn; its capsule is. See ADR 0062.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage else { return super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin) }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var hidden: [NSRange] = []
        storage.enumerateAttribute(.inkhashDue, in: characters) { value, range, _ in
            if value != nil { hidden.append(glyphRange(forCharacterRange: range, actualCharacterRange: nil)) }
        }
        guard !hidden.isEmpty else { return super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin) }
        var cursor = glyphsToShow.location
        for range in hidden {
            if range.location > cursor {
                super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: range.location - cursor), at: origin)
            }
            cursor = max(cursor, NSMaxRange(range))
        }
        if cursor < NSMaxRange(glyphsToShow) {
            super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: NSMaxRange(glyphsToShow) - cursor), at: origin)
        }
    }

    /// A capsule with a calendar and the day in words where `📅 JJJJ-MM-TT` stands, like in the task list.
    private func drawDueDays(in paragraph: NSRange, storage: NSTextStorage, checked: Bool, origin: CGPoint) {
        let today = TaskDue.day(of: Date())
        storage.enumerateAttribute(.inkhashDue, in: paragraph) { value, range, _ in
            guard let day = value as? String, let container = textContainers.first else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let bounds = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            let body = EditorFont.font(for: .checkbox, bold: false, italic: false, code: false)
            let baseline = origin.y + lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil).minY + location(forGlyphAt: glyphs.location).y
            let color = checked ? Self.mutedColor : (day <= today ? RichText.accentColor : RichText.inkColor)
            let font = EditorFont.font(size: EditorFont.scaled(11.5), serif: false, bold: false, italic: false, code: false)
            let label = NSAttributedString(string: DueText.short(day, today: today), attributes: [.font: font, .foregroundColor: color])
            let icon = EditorFont.scaled(11)
            let gap = EditorFont.scaled(4)
            let padding = EditorFont.scaled(8)
            // As wide as what it says, from where the hidden characters begin.
            let height = EditorFont.scaled(20)
            let width = padding * 2 + icon + gap + label.size().width
            let capsule = CGRect(x: bounds.minX, y: baseline - body.xHeight / 2 - height / 2, width: width, height: height)
            drawCapsule(capsule)
            let left = capsule.minX + padding
            drawSymbol("calendar", color: color, in: CGRect(x: left, y: capsule.midY - icon / 2, width: icon, height: icon))
            label.draw(at: CGPoint(x: left + icon + gap, y: capsule.midY - label.size().height / 2))
        }
    }

    private func drawCapsule(_ rect: CGRect) {
        #if os(macOS)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        #else
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        #endif
        Self.capsuleFill.setFill()
        path.fill()
        Self.capsuleRule.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawSymbol(_ name: String, color: PlatformColor, in rect: CGRect) {
        #if os(macOS)
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #else
        let configuration = UIImage.SymbolConfiguration(pointSize: rect.height, weight: .medium)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        image.draw(in: rect)
        #endif
    }

    private static var capsuleFill: PlatformColor { PlatformColor(red: 0.992, green: 0.984, blue: 0.969, alpha: 1) }
    private static var capsuleRule: PlatformColor { PlatformColor(red: 0.059, green: 0.129, blue: 0.220, alpha: 0.12) }

    private func draw(_ text: String, font: PlatformFont, color: PlatformColor, right: CGFloat, baseline: CGFloat) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let width = string.size().width
        string.draw(at: CGPoint(x: right - width, y: baseline - font.ascender))
    }

    /// Like in the task list: a grey rounded square while open, filled blue with a white tick when done.
    /// Drawn as paths, not as symbols: the symbols came out smaller on the Mac, and the filled one lost
    /// its tick there. See ADR 0062.
    private func drawCheckbox(checked: Bool, in rect: CGRect) {
        let box = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
        let radius = box.width * 0.22
        #if os(macOS)
        let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
        #else
        let path = UIBezierPath(roundedRect: box, cornerRadius: radius)
        #endif
        if checked {
            RichText.accentColor.setFill()
            path.fill()
            #if os(macOS)
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: box.minX + box.width * 0.26, y: box.minY + box.height * 0.53))
            tick.line(to: CGPoint(x: box.minX + box.width * 0.43, y: box.minY + box.height * 0.7))
            tick.line(to: CGPoint(x: box.minX + box.width * 0.75, y: box.minY + box.height * 0.32))
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            #else
            let tick = UIBezierPath()
            tick.move(to: CGPoint(x: box.minX + box.width * 0.26, y: box.minY + box.height * 0.53))
            tick.addLine(to: CGPoint(x: box.minX + box.width * 0.43, y: box.minY + box.height * 0.7))
            tick.addLine(to: CGPoint(x: box.minX + box.width * 0.75, y: box.minY + box.height * 0.32))
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            #endif
            tick.lineWidth = max(1.5, box.width * 0.12)
            PlatformColor.white.setStroke()
            tick.stroke()
        } else {
            path.lineWidth = max(1.2, box.width * 0.08)
            Self.mutedColor.setStroke()
            path.stroke()
        }
    }

    /// Grid of one table row: lines between the cells and around the row, a tint behind the header.
    /// A quiet table: a firm line under the header, hairlines between rows, no vertical grid. Zebra
    /// rows get a light wash. The column boundaries come from `TableRowLayout`. See ADR 0036.
    private func drawTableRow(_ paragraph: NSRange, in storage: NSTextStorage, origin: CGPoint) {
        let glyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        var rowRect = CGRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in rowRect = rowRect.union(rect) }
        guard !rowRect.isNull, let style = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle,
              let layout = storage.attribute(.inkhashTableRow, at: paragraph.location, effectiveRange: nil) as? TableRowLayout else { return }
        let left = origin.x + NoteDocument.gutter
        let right = left + (layout.edges.last ?? 0)
        // The header carries extra space above; the row starts at the text.
        let top = origin.y + rowRect.minY + style.paragraphSpacingBefore
        let bottom = origin.y + rowRect.maxY
        let isHeader = layout.index == 0 && layout.header
        let bodyIndex = layout.header ? layout.index - 1 : layout.index
        if isHeader {
            Self.headerWash.setFill()
            fill(CGRect(x: left, y: top, width: right - left, height: bottom - top))
            Self.headerRule.setFill()
            fill(CGRect(x: left, y: bottom - 1.5, width: right - left, height: 1.5))
            return
        }
        if layout.zebra, bodyIndex % 2 == 1 {
            Self.zebraWash.setFill()
            fill(CGRect(x: left, y: top, width: right - left, height: bottom - top))
        }
        if !layout.last {
            Self.rowRule.setFill()
            fill(CGRect(x: left, y: bottom - 0.5, width: right - left, height: 0.5))
        } else if !layout.header || layout.index > 0 {
            Self.headerRule.setFill()
            fill(CGRect(x: left, y: bottom - 1, width: right - left, height: 1))
        }
    }

    private static var headerWash: PlatformColor { PlatformColor(red: 0.306, green: 0.420, blue: 0.478, alpha: 0.05) }
    private static var headerRule: PlatformColor { PlatformColor(red: 0.059, green: 0.129, blue: 0.220, alpha: 0.28) }
    private static var rowRule: PlatformColor { PlatformColor(red: 0.059, green: 0.129, blue: 0.220, alpha: 0.09) }
    private static var zebraWash: PlatformColor { PlatformColor(red: 0.059, green: 0.129, blue: 0.220, alpha: 0.03) }

    private func fill(_ rect: CGRect) {
        #if os(macOS)
        NSBezierPath(rect: rect).fill()
        #else
        UIBezierPath(rect: rect).fill()
        #endif
    }

    private func drawCodeBackground(_ paragraph: NSRange, origin: CGPoint) {
        let glyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        Self.codeColor.setFill()
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            var fill = rect.offsetBy(dx: origin.x, dy: origin.y)
            fill.origin.x += NoteDocument.gutter - 8
            fill.size.width -= NoteDocument.gutter - 8
            #if os(macOS)
            NSBezierPath(rect: fill).fill()
            #else
            UIBezierPath(rect: fill).fill()
            #endif
        }
    }

    /// Every match gets a soft mark, the current one a strong one. Not the highlighter's yellow, which is text.
    private func drawFindMatches(in glyphsToShow: NSRange, origin: CGPoint) {
        guard !findMatches.isEmpty, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        for match in findMatches where NSIntersectionRange(match, characters).length > 0 {
            let glyphs = glyphRange(forCharacterRange: match, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            (match == findCurrent ? Self.findCurrentColor : Self.findColor).setFill()
            enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                let fill = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -2, dy: 0)
                #if os(macOS)
                NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
                #else
                UIBezierPath(roundedRect: fill, cornerRadius: 3).fill()
                #endif
            }
        }
    }

    private static var findColor: PlatformColor {
        PlatformColor(red: 0.306, green: 0.420, blue: 0.478, alpha: 0.18)
    }

    private static var findCurrentColor: PlatformColor {
        PlatformColor(red: 0.914, green: 0.718, blue: 0.427, alpha: 0.9)
    }

    private static var mutedColor: PlatformColor {
        PlatformColor(red: 0.404, green: 0.447, blue: 0.482, alpha: 1)
    }

    private static var codeColor: PlatformColor {
        PlatformColor(red: 0.059, green: 0.129, blue: 0.220, alpha: 0.045)
    }
}
