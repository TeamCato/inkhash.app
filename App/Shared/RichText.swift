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
            link: attributes[.inkhashLink] as? String
        )
    }
}

enum EditorFont {
    static func size(for type: BlockType) -> CGFloat {
        switch type {
        case .heading1: return 30
        case .heading2: return 24
        case .heading3: return 20
        case .code: return 15
        case .tableRow: return 16
        default: return 18
        }
    }

    static func font(size: CGFloat, bold: Bool, italic: Bool, code: Bool) -> PlatformFont {
        if code {
            return PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        #if os(macOS)
        let preferred = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
        let base = preferred.withDesign(.serif) ?? preferred
        var traits = NSFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        return NSFont(descriptor: base.withSymbolicTraits(traits), size: size)
            ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        #else
        let preferred = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        let base = preferred.withDesign(.serif) ?? preferred
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

enum RichText {
    /// Headings carry their weight as part of the block, not as `**`. See P-030.
    static func isHeading(_ type: BlockType) -> Bool {
        type == .heading1 || type == .heading2 || type == .heading3
    }

    static func attributed(_ spans: [InlineSpan], type: BlockType) -> NSAttributedString {
        let size = EditorFont.size(for: type)
        let heading = isHeading(type)
        let result = NSMutableAttributedString()
        defer { highlightMarkers(in: result, type: type) }
        let source = spans.isEmpty ? [InlineSpan(text: "")] : spans
        for span in source {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: EditorFont.font(size: size, bold: span.bold || heading, italic: span.italic, code: span.code || type == .code),
                .foregroundColor: inkColor,
            ]
            if span.code || type == .code {
                attributes[.inkhashCode] = true
            }
            if let link = span.link, type != .code {
                attributes.merge(linkAttributes(link)) { _, new in new }
            }
            result.append(NSAttributedString(string: span.text, attributes: attributes))
        }
        if result.length == 0 {
            result.append(NSAttributedString(string: "", attributes: [
                .font: EditorFont.font(size: size, bold: heading, italic: false, code: type == .code),
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

    private static let markerPattern = try! NSRegularExpression(
        pattern: #"\*{1,3}|`|(?<![\w#])#[^\s#]+"#
    )

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
            .font: EditorFont.font(size: EditorFont.size(for: type), bold: isHeading(type), italic: false, code: type == .code),
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
            spans.append(InlineSpan(
                text: text,
                bold: heading ? false : (font.map(isBold) ?? false),
                italic: font.map(isItalic) ?? false,
                code: code,
                link: attributes[.inkhashLink] as? String
            ))
        }
        return MarkdownCodec.normalize(spans)
    }

    static func reconcile(_ attr: NSAttributedString, cursor: Int, type: BlockType) -> (spans: [InlineSpan], cursor: Int)? {
        guard attr.string.contains(where: { "*`\\)".contains($0) }) else { return nil }
        let parsed = MarkdownCodec.parseInline(markdown(from: attr, type: type), cursorUTF16: cursor)
        guard parsed.plain != attr.string else { return nil }
        return (parsed.spans, parsed.cursorUTF16)
    }

    /// The text as Markdown for the live reparse. Unlike `serializeInline` it does not escape:
    /// what the person typed as `*` is meant as a marker here.
    private static func markdown(from attr: NSAttributedString, type: BlockType) -> String {
        let heading = isHeading(type)
        var output = ""
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
            if code {
                output += "`\(text)`"
            } else if bold && italic {
                output += "***\(text)***"
            } else if bold {
                output += "**\(text)**"
            } else if italic {
                output += "*\(text)*"
            } else {
                output += text
            }
        }
        if let openLink { output += "](\(openLink))" }
        return output
    }

    static var accentColor: PlatformColor {
        #if os(macOS)
        NSColor(srgbRed: 0.24, green: 0.435, blue: 0.66, alpha: 1)
        #else
        UIColor(red: 0.24, green: 0.435, blue: 0.66, alpha: 1)
        #endif
    }

    static var mutedColor: PlatformColor {
        PlatformColor(red: 0.42, green: 0.44, blue: 0.47, alpha: 1)
    }

    static var inkColor: PlatformColor {
        #if os(macOS)
        NSColor(srgbRed: 0.11, green: 0.115, blue: 0.125, alpha: 1)
        #else
        UIColor(red: 0.11, green: 0.115, blue: 0.125, alpha: 1)
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
    /// Paragraph attributes, on every character of a paragraph including its newline. See ADR 0025.
    static let inkhashBlockType = NSAttributedString.Key("inkhash.blockType")
    static let inkhashChecked = NSAttributedString.Key("inkhash.checked")
    static let inkhashLanguage = NSAttributedString.Key("inkhash.language")
    /// Column count of the table a row belongs to; the layout manager draws the grid from it.
    static let inkhashTableColumns = NSAttributedString.Key("inkhash.tableColumns")
    /// On the first row of a table: its `TableFormat`, boxed. See ADR 0036.
    static let inkhashTable = NSAttributedString.Key("inkhash.table")
    /// On every row: where the columns lie and how the row is drawn (`TableRowLayout`).
    static let inkhashTableRow = NSAttributedString.Key("inkhash.tableRow")
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
