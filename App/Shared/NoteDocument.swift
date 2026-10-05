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

    static let paragraph = BlockStyle(type: .paragraph)

    init(type: BlockType, checked: Bool = false, language: String = "", table: TableFormat? = nil) {
        self.type = type
        self.checked = checked
        self.language = language
        self.table = table
    }

    init(_ attributes: [NSAttributedString.Key: Any]) {
        type = (attributes[.inkhashBlockType] as? String).flatMap(BlockType.init(rawValue:)) ?? .paragraph
        checked = attributes[.inkhashChecked] as? Bool ?? false
        language = attributes[.inkhashLanguage] as? String ?? ""
        table = type == .tableRow ? (attributes[.inkhashTable] as? TableFormatBox)?.style : nil
    }

    init(_ block: Block) {
        self.init(type: block.type, checked: block.checked, language: block.language, table: block.table)
    }

    var attributes: [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [
            .inkhashBlockType: type.rawValue,
            .inkhashChecked: checked,
            .inkhashLanguage: language,
            .paragraphStyle: NoteDocument.paragraphStyle(type),
        ]
        if let table { result[.inkhashTable] = TableFormatBox(table) }
        return result
    }

    var hasMarker: Bool { type == .bullet || type == .numbered || type == .checkbox }
}

/// Converts between the blocks of a note and the one attributed text the editor shows. See ADR 0025.
enum NoteDocument {
    /// Left indent of every paragraph. Markers are drawn inside it; title and path start at it.
    static let gutter: CGFloat = 38
    /// Space between a marker and the text.
    static let markerGap: CGFloat = 10

    static func paragraphStyle(_ type: BlockType) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = gutter
        style.headIndent = gutter
        style.lineSpacing = 2
        switch type {
        case .heading1: style.paragraphSpacingBefore = 22
        case .heading2: style.paragraphSpacingBefore = 16
        case .heading3: style.paragraphSpacingBefore = 12
        case .code: style.paragraphSpacingBefore = 2
        default: style.paragraphSpacingBefore = 6
        }
        return style
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
        style.paragraphSpacingBefore = header ? 10 : 0
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
            blocks.append(Block(type: style.type, spans: spans, checked: style.checked, table: style.table))
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

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
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
            }
            cursor = NSMaxRange(paragraph)
        }
        let atEnd = NSMaxRange(glyphsToShow) >= numberOfGlyphs
        let fragment = extraLineFragmentRect
        if atEnd, trailing.hasMarker, fragment.height > 0 {
            let font = EditorFont.font(size: EditorFont.size(for: trailing.type), bold: false, italic: false, code: false)
            let baseline = fragment.maxY - abs(font.descender) - 2
            drawMarker(trailing, number: number(endingAt: ns.length, in: storage), baseline: baseline, origin: origin)
        }
    }

    /// 1 for the first of a run of numbered paragraphs. Matches how the codec numbers them.
    private func number(endingAt location: Int, in storage: NSTextStorage) -> Int {
        let ns = storage.string as NSString
        var count = 1
        var cursor = location
        while cursor > 0 {
            let previous = ns.paragraphRange(for: NSRange(location: cursor - 1, length: 0))
            guard BlockStyle(storage.attributes(at: previous.location, effectiveRange: nil)).type == .numbered else { break }
            count += 1
            cursor = previous.location
        }
        return count
    }

    private func drawMarker(_ style: BlockStyle, number: Int, baseline: CGFloat, origin: CGPoint) {
        let size = EditorFont.size(for: style.type)
        let right = origin.x + NoteDocument.gutter - NoteDocument.markerGap
        let y = origin.y + baseline
        switch style.type {
        case .bullet:
            draw("•", font: EditorFont.font(size: size, bold: false, italic: false, code: false), color: RichText.inkColor, right: right, baseline: y)
        case .numbered:
            draw("\(number).", font: EditorFont.font(size: size * 0.85, bold: false, italic: false, code: false), color: Self.mutedColor, right: right, baseline: y)
        case .checkbox:
            let side: CGFloat = 16
            let font = EditorFont.font(size: size, bold: false, italic: false, code: false)
            let rect = CGRect(x: right - side, y: y - font.xHeight / 2 - side / 2, width: side, height: side)
            drawCheckbox(checked: style.checked, in: rect)
        default:
            break
        }
    }

    private func draw(_ text: String, font: PlatformFont, color: PlatformColor, right: CGFloat, baseline: CGFloat) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let width = string.size().width
        string.draw(at: CGPoint(x: right - width, y: baseline - font.ascender))
    }

    private func drawCheckbox(checked: Bool, in rect: CGRect) {
        let name = checked ? "checkmark.square.fill" : "square"
        #if os(macOS)
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [RichText.accentColor]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #else
        let configuration = UIImage.SymbolConfiguration(pointSize: rect.height, weight: .regular)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(RichText.accentColor, renderingMode: .alwaysOriginal) else { return }
        image.draw(in: rect)
        #endif
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

    private static var headerWash: PlatformColor { PlatformColor(red: 0.24, green: 0.435, blue: 0.66, alpha: 0.05) }
    private static var headerRule: PlatformColor { PlatformColor(red: 0.11, green: 0.115, blue: 0.125, alpha: 0.28) }
    private static var rowRule: PlatformColor { PlatformColor(red: 0.11, green: 0.115, blue: 0.125, alpha: 0.09) }
    private static var zebraWash: PlatformColor { PlatformColor(red: 0.11, green: 0.115, blue: 0.125, alpha: 0.03) }

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

    private static var mutedColor: PlatformColor {
        PlatformColor(red: 0.42, green: 0.44, blue: 0.47, alpha: 1)
    }

    private static var codeColor: PlatformColor {
        PlatformColor(red: 0.11, green: 0.115, blue: 0.125, alpha: 0.045)
    }
}
