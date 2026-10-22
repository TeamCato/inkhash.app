import InkhashCore
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

struct InlineSelection: Equatable {
    var length: Int
    var bold: Bool
    var italic: Bool
    var code: Bool
    var link: String?
    var decorations: Set<InlineDecoration> = []

    static let none = InlineSelection(length: 0, bold: false, italic: false, code: false)

    /// Reads the styles at the start of `range`. An empty range reads the typing attributes instead.
    static func read(_ attr: NSAttributedString, range: NSRange, typing: [NSAttributedString.Key: Any]) -> InlineSelection {
        let attributes: [NSAttributedString.Key: Any]
        if range.length > 0, range.location < attr.length {
            attributes = attr.attributes(at: range.location, effectiveRange: nil)
        } else {
            attributes = typing
        }
        let font = attributes[.font] as? PlatformFont
        return InlineSelection(
            length: range.length,
            bold: font.map(RichText.isBold) ?? false,
            italic: font.map(RichText.isItalic) ?? false,
            code: attributes[.inkhashCode] != nil,
            link: attributes[.inkhashLink] as? String,
            decorations: RichText.decorations(in: attributes)
        )
    }
}

/// Headings in the system serif, everything else in the system sans. On iOS sizes follow Dynamic Type. See ADR 0053.
enum EditorFont {
    /// Size at the default text size. Body is 17 like the system's body style.
    static func baseSize(for type: BlockType) -> CGFloat {
        switch type {
        case .heading1: return 30
        case .heading2: return 24
        case .heading3: return 20
        case .code: return 15
        case .tableRow: return 16
        default: return 17
        }
    }

    static func size(for type: BlockType) -> CGFloat {
        scaled(baseSize(for: type))
    }

    /// A length that grows with the size chosen in the settings (ADR 0061) and, on iPad and iPhone,
    /// with the system's text size. The Mac has no Dynamic Type.
    static func scaled(_ value: CGFloat) -> CGFloat {
        let chosen = value * TextAppearance.current.scale
        #if os(macOS)
        return chosen
        #else
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: chosen)
        #endif
    }

    /// Line height as a multiple of the size: airy for reading, tight for headings.
    static func lineHeightFactor(for type: BlockType) -> CGFloat {
        switch type {
        case .heading1, .heading2, .heading3: return 1.2
        case .code: return 1.4
        default: return 1.5
        }
    }

    /// Space below each line that brings the font's own line height up to `lineHeightFactor`.
    /// Line spacing, not a line height multiple: that would put the space above the glyphs and
    /// stretch the caret and the markers with it.
    static func lineSpacing(for type: BlockType) -> CGFloat {
        let font = font(for: type, bold: false, italic: false, code: type == .code)
        return max(0, (font.pointSize * lineHeightFactor(for: type) - lineHeight(of: font)).rounded())
    }

    static func lineHeight(of font: PlatformFont) -> CGFloat {
        #if os(macOS)
        font.ascender - font.descender + font.leading
        #else
        font.lineHeight
        #endif
    }

    static func font(for type: BlockType, bold: Bool, italic: Bool, code: Bool) -> PlatformFont {
        font(size: size(for: type), serif: RichText.isHeading(type), bold: bold, italic: italic, code: code)
    }

    static func font(size: CGFloat, serif: Bool, bold: Bool, italic: Bool, code: Bool) -> PlatformFont {
        if code {
            return PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        let design = serif ? .serif : TextAppearance.current.family.design
        #if os(macOS)
        let preferred = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
        let base = preferred.withDesign(design) ?? preferred
        var traits = NSFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        return NSFont(descriptor: base.withSymbolicTraits(traits), size: size)
            ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        #else
        let preferred = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        let base = preferred.withDesign(design) ?? preferred
        var traits = UIFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let described = base.withSymbolicTraits(traits) {
            return UIFont(descriptor: described, size: size)
        }
        return .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        #endif
    }
}

extension TextFamily {
    #if os(macOS)
    var design: NSFontDescriptor.SystemDesign {
        switch self {
        case .standard: .default
        case .serif: .serif
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }
    #else
    var design: UIFontDescriptor.SystemDesign {
        switch self {
        case .standard: .default
        case .serif: .serif
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }
    #endif
}

enum RichText {
    /// Headings carry their weight as part of the block, not as `**`. See P-030.
    static func isHeading(_ type: BlockType) -> Bool {
        type == .heading1 || type == .heading2 || type == .heading3
    }

    static func attributed(_ spans: [InlineSpan], type: BlockType) -> NSAttributedString {
        let heading = isHeading(type)
        let result = NSMutableAttributedString()
        defer { highlightMarkers(in: result, type: type) }
        let source = spans.isEmpty ? [InlineSpan(text: "")] : spans
        for span in source {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: EditorFont.font(for: type, bold: span.bold || heading, italic: span.italic, code: span.code || type == .code),
                .foregroundColor: inkColor,
            ]
            if span.code || type == .code {
                attributes[.inkhashCode] = true
            }
            if let link = span.link, type != .code {
                attributes.merge(linkAttributes(link)) { _, new in new }
            }
            if type != .code {
                for decoration in InlineDecoration.allCases where decoration.isOn(span) {
                    attributes[decoration.attributeKey] = true
                }
            }
            result.append(NSAttributedString(string: span.text, attributes: attributes))
        }
        if result.length == 0 {
            result.append(NSAttributedString(string: "", attributes: [
                .font: EditorFont.font(for: type, bold: heading, italic: false, code: type == .code),
                .foregroundColor: inkColor,
            ]))
        }
        return result
    }

    /// Tints what the editor recognises while it is still being typed: open `*`, `**`, `` ` `` markers
    /// and `#tag` words. Colour only, so `spans(from:)` does not see it. See ADR 0018.
    static func highlightMarkers(in storage: NSMutableAttributedString, range: NSRange? = nil, type: BlockType) {
        let full = range ?? NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        storage.removeAttribute(.foregroundColor, range: full)
        storage.addAttribute(.foregroundColor, value: inkColor, range: full)
        if type == .code { return }
        storage.enumerateAttribute(.inkhashLink, in: full, options: []) { value, range, _ in
            if value != nil { storage.addAttribute(.foregroundColor, value: accentColor, range: range) }
        }
        for match in markerPattern.matches(in: storage.string, range: full) where match.range.length > 0 {
            var inCode = false
            storage.enumerateAttribute(.inkhashCode, in: match.range, options: []) { value, _, stop in
                if value != nil { inCode = true; stop.pointee = true }
            }
            if inCode { continue }
            storage.addAttribute(.foregroundColor, value: accentColor, range: match.range)
        }
    }

    /// A task as in the task list: done ones grey and struck through, the due day as a capsule the
    /// layout manager draws. Display only; `blocks(from:)` reads neither. Other paragraphs lose both.
    /// See ADR 0062.
    static func decorateTask(in storage: NSMutableAttributedString, range: NSRange, style: BlockStyle) {
        guard range.length > 0 else { return }
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.strikethroughColor, range: range)
        storage.removeAttribute(.inkhashDue, range: range)
        defer { paintDecorations(in: storage, range: range) }
        guard style.type == .checkbox else { return }
        if style.checked {
            storage.addAttributes([
                .foregroundColor: mutedColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: mutedColor,
            ], range: range)
        }
        let text = (storage.string as NSString).substring(with: range) as NSString
        guard let found = TaskDue.trailingRange(in: text as String) else { return }
        let marker = text.range(of: TaskDue.marker, range: found.whole)
        guard marker.location != NSNotFound else { return }
        let chip = NSRange(location: range.location + marker.location, length: NSMaxRange(found.day) - marker.location)
        storage.removeAttribute(.strikethroughStyle, range: chip)
        storage.addAttributes([
            .inkhashDue: text.substring(with: found.day),
            .font: EditorFont.font(size: EditorFont.scaled(12), serif: false, bold: false, italic: false, code: false),
        ], range: chip)
    }

    private static let markerPattern = try! NSRegularExpression(
        pattern: #"\*{1,3}|`|~~|==|</?u>|(?<![\w#])#[^\s#]+"#
    )

    static var highlightColor: PlatformColor {
        PlatformColor(red: 0.98, green: 0.86, blue: 0.45, alpha: 0.45)
    }

    /// Draws underline, strikethrough and highlighter from the `inkhash.*` keys. The drawing attributes
    /// are shared with links and done tasks, so the keys stay the truth and survive their removal. See ADR 0079.
    static func paintDecorations(in storage: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        storage.removeAttribute(.backgroundColor, range: range)
        storage.enumerateAttributes(in: range, options: []) { attributes, run, _ in
            let decorations = decorations(in: attributes)
            if decorations.contains(.underline) || attributes[.inkhashLink] != nil {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: run)
            } else {
                storage.removeAttribute(.underlineStyle, range: run)
            }
            if decorations.contains(.strike), attributes[.inkhashDue] == nil {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run)
            }
            if decorations.contains(.highlight) {
                storage.addAttribute(.backgroundColor, value: highlightColor, range: run)
            }
        }
    }

    static func decorations(in attributes: [NSAttributedString.Key: Any]) -> Set<InlineDecoration> {
        Set(InlineDecoration.allCases.filter { attributes[$0.attributeKey] != nil })
    }

    /// A link is accent coloured and underlined. The target travels in `.inkhashLink`, not `.link`,
    /// so a plain click still places the cursor; on the Mac the pointer and a tooltip tell the target.
    static func linkAttributes(_ target: String) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .inkhashLink: target,
            .foregroundColor: accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        #if os(macOS)
        attributes[.toolTip] = target
        attributes[.cursor] = NSCursor.pointingHand
        #endif
        return attributes
    }

    static let linkAttributeKeys: [NSAttributedString.Key] = {
        var keys: [NSAttributedString.Key] = [.inkhashLink, .underlineStyle]
        #if os(macOS)
        keys += [.toolTip, .cursor]
        #endif
        return keys
    }()

    static func typingAttributes(for type: BlockType) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: EditorFont.font(for: type, bold: isHeading(type), italic: false, code: type == .code),
            .foregroundColor: inkColor,
        ]
        if type == .code { attributes[.inkhashCode] = true }
        return attributes
    }

    static func spans(from attr: NSAttributedString, type: BlockType) -> [InlineSpan] {
        let heading = isHeading(type)
        guard attr.length > 0 else { return [InlineSpan(text: "")] }
        var spans: [InlineSpan] = []
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { attributes, range, _ in
            let text = attr.attributedSubstring(from: range).string
            guard !text.isEmpty else { return }
            let font = attributes[.font] as? PlatformFont
            let code = attributes[.inkhashCode] != nil
            let decorations = decorations(in: attributes)
            spans.append(InlineSpan(
                text: text,
                bold: heading ? false : (font.map(isBold) ?? false),
                italic: font.map(isItalic) ?? false,
                code: code,
                link: attributes[.inkhashLink] as? String,
                underline: decorations.contains(.underline),
                strike: decorations.contains(.strike),
                highlight: decorations.contains(.highlight)
            ))
        }
        return MarkdownCodec.normalize(spans)
    }

    static func reconcile(_ attr: NSAttributedString, cursor: Int, type: BlockType) -> (spans: [InlineSpan], cursor: Int)? {
        guard attr.string.contains(where: { "*`\\)~=>".contains($0) }) else { return nil }
        let source = markdown(from: attr, cursor: cursor, type: type)
        let parsed = MarkdownCodec.parseInline(source.text, cursorUTF16: source.cursor)
        guard parsed.plain != attr.string else { return nil }
        return (parsed.spans, parsed.cursorUTF16)
    }

    /// The text as Markdown for the live reparse, and where `cursor` lies in it: styles already in the
    /// text add markers before it. Unlike `serializeInline` it does not escape: what the person typed
    /// as `*` is meant as a marker here.
    private static func markdown(from attr: NSAttributedString, cursor: Int, type: BlockType) -> (text: String, cursor: Int) {
        let heading = isHeading(type)
        var output = ""
        var sourceCursor: Int?
        var openLink: String?
        let full = NSRange(location: 0, length: attr.length)
        attr.enumerateAttributes(in: full) { attributes, range, _ in
            let text = attr.attributedSubstring(from: range).string
            let font = attributes[.font] as? PlatformFont
            let code = attributes[.inkhashCode] != nil
            let bold = heading ? false : (font.map(isBold) ?? false)
            let italic = font.map(isItalic) ?? false
            let link = attributes[.inkhashLink] as? String
            if openLink != link {
                if let openLink { output += "](\(openLink))" }
                if link != nil { output += "[" }
                openLink = link
            }
            var marker = ""
            if code {
                marker = "`"
            } else if bold && italic {
                marker = "***"
            } else if bold {
                marker = "**"
            } else if italic {
                marker = "*"
            }
            var prefix = marker
            var suffix = marker
            for decoration in InlineDecoration.allCases.reversed() where attributes[decoration.attributeKey] != nil {
                prefix = decoration.opener + prefix
                suffix += decoration.closer
            }
            if sourceCursor == nil, cursor < NSMaxRange(range) {
                // At the start of a run the cursor stands before its markers.
                let offset = cursor - range.location
                sourceCursor = (output as NSString).length + (offset > 0 ? (prefix as NSString).length + offset : 0)
            }
            output += prefix + text + suffix
        }
        if let openLink { output += "](\(openLink))" }
        return (output, sourceCursor ?? (output as NSString).length)
    }

    static var accentColor: PlatformColor {
        #if os(macOS)
        NSColor(srgbRed: 0.306, green: 0.420, blue: 0.478, alpha: 1)
        #else
        UIColor(red: 0.306, green: 0.420, blue: 0.478, alpha: 1)
        #endif
    }

    static var mutedColor: PlatformColor {
        PlatformColor(red: 0.404, green: 0.447, blue: 0.482, alpha: 1)
    }

    static var inkColor: PlatformColor {
        #if os(macOS)
        NSColor(srgbRed: 0.059, green: 0.129, blue: 0.220, alpha: 1)
        #else
        UIColor(red: 0.059, green: 0.129, blue: 0.220, alpha: 1)
        #endif
    }

    static func isBold(_ font: PlatformFont) -> Bool {
        #if os(macOS)
        font.fontDescriptor.symbolicTraits.contains(.bold)
        #else
        font.fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }

    static func isItalic(_ font: PlatformFont) -> Bool {
        #if os(macOS)
        font.fontDescriptor.symbolicTraits.contains(.italic)
        #else
        font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        #endif
    }
}

extension NSAttributedString.Key {
    static let inkhashCode = NSAttributedString.Key("inkhash.code")
    static let inkhashLink = NSAttributedString.Key("inkhash.link")
    /// Inline decorations; `RichText.paintDecorations` draws them. See ADR 0079.
    static let inkhashUnderline = NSAttributedString.Key("inkhash.underline")
    static let inkhashStrike = NSAttributedString.Key("inkhash.strike")
    static let inkhashHighlight = NSAttributedString.Key("inkhash.highlight")
    /// Paragraph attributes, on every character of a paragraph including its newline. See ADR 0025.
    static let inkhashBlockType = NSAttributedString.Key("inkhash.blockType")
    static let inkhashChecked = NSAttributedString.Key("inkhash.checked")
    /// On the `📅 JJJJ-MM-TT` of a task: the day. The layout manager draws a capsule there instead. See ADR 0062.
    static let inkhashDue = NSAttributedString.Key("inkhash.due")
    static let inkhashLanguage = NSAttributedString.Key("inkhash.language")
    /// Column count of the table a row belongs to; the layout manager draws the grid from it.
    static let inkhashTableColumns = NSAttributedString.Key("inkhash.tableColumns")
    /// On the first row of a table: its `TableFormat`, boxed. See ADR 0036.
    static let inkhashTable = NSAttributedString.Key("inkhash.table")
    /// On every row: where the columns lie and how the row is drawn (`TableRowLayout`).
    static let inkhashTableRow = NSAttributedString.Key("inkhash.tableRow")
}

extension InlineDecoration {
    var attributeKey: NSAttributedString.Key {
        switch self {
        case .underline: .inkhashUnderline
        case .strike: .inkhashStrike
        case .highlight: .inkhashHighlight
        }
    }

    /// What `RichText.paintDecorations` draws for this decoration, for typing before any text exists.
    var drawingAttributes: [NSAttributedString.Key: Any] {
        switch self {
        case .underline: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        case .strike: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .highlight: [.backgroundColor: RichText.highlightColor]
        }
    }

    var drawingKeys: [NSAttributedString.Key] { Array(drawingAttributes.keys) }
}

/// A value type in an attributed string needs a class around it to survive copies through Foundation.
final class TableFormatBox: NSObject {
    let style: TableFormat
    init(_ style: TableFormat) { self.style = style }
    override func isEqual(_ object: Any?) -> Bool { (object as? TableFormatBox)?.style == style }
}

/// What the layout manager needs to draw one table row.
final class TableRowLayout: NSObject {
    /// Column boundaries from the text's left edge, first is 0, last the table width.
    let edges: [CGFloat]
    let index: Int
    let header: Bool
    let zebra: Bool
    let last: Bool

    init(edges: [CGFloat], index: Int, header: Bool, zebra: Bool, last: Bool) {
        self.edges = edges
        self.index = index
        self.header = header
        self.zebra = zebra
        self.last = last
    }
}


enum Links {
    static func url(_ target: String) -> URL? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") || trimmed.hasPrefix("mailto:") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }
}
