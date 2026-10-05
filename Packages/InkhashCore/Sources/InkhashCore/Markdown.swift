import Foundation

public struct InlineSpan: Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public var italic: Bool
    public var code: Bool
    /// Target of `[text](link)`. Nil for plain text. See ADR 0024.
    public var link: String?

    public init(text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, link: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.code = code
        self.link = link
    }

    /// Same styles and link, so the two could be one span.
    public func sameStyle(as other: InlineSpan) -> Bool {
        bold == other.bold && italic == other.italic && code == other.code && link == other.link
    }
}

public struct InlineParse: Equatable, Sendable {
    public var spans: [InlineSpan]
    public var plain: String
    public var cursorUTF16: Int
}

public enum BlockType: String, Codable, Sendable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bullet
    case numbered
    case checkbox
    case code
    /// One row of a Markdown table. Cells are separated by a tab in the spans; consecutive rows
    /// form one table, the first is its header. See ADR 0027.
    case tableRow
    /// A paragraph that is only `![label](excerpt target)`: a window onto a handwriting page.
    /// The single span carries the label and the target. See ADR 0032.
    case excerpt
}

public struct Block: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var type: BlockType
    public var spans: [InlineSpan]
    public var checked: Bool
    public var language: String
    /// On the first row of a table: how the table looks. See ADR 0036.
    public var table: TableFormat?

    public init(
        id: UUID = UUID(),
        type: BlockType,
        spans: [InlineSpan],
        checked: Bool = false,
        language: String = "",
        table: TableFormat? = nil
    ) {
        self.id = id
        self.type = type
        self.spans = MarkdownCodec.normalize(spans)
        self.checked = checked
        self.language = language
        self.table = table
    }

    public var plain: String { spans.map(\.text).joined() }
}

public enum BlockShortcut {
    public static func type(forToken token: String) -> BlockType? {
        switch token {
        case "#": return .heading1
        case "##": return .heading2
        case "###": return .heading3
        case "-", "*": return .bullet
        case "[ ]", "[]", "- [ ]", "x": return .checkbox
        case "```": return .code
        default:
            if token.range(of: #"^\d+\.$"#, options: .regularExpression) != nil {
                return .numbered
            }
            return nil
        }
    }
}

public enum MarkdownCodec {
    public static func parse(_ markdown: String) -> [Block] {
        let text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [Block(type: .paragraph, spans: [InlineSpan(text: "")])]
        }
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let fence = line.trimmingCharacters(in: .whitespaces)
                let language = String(fence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var body: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces) != "```" {
                    body.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(Block(type: .code, spans: [InlineSpan(text: body.joined(separator: "\n"))], language: language))
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            // A table: a row of cells followed by a separator line. Without the separator it is text.
            if isTableLine(line), index + 1 < lines.count, isSeparatorLine(lines[index + 1]) {
                var style = TableFormat(alignments: TableFormat.alignments(fromSeparator: lines[index + 1]))
                let first = blocks.count
                blocks.append(tableRow(line))
                index += 2
                while index < lines.count, isTableLine(lines[index]) {
                    if !isSeparatorLine(lines[index]) { blocks.append(tableRow(lines[index])) }
                    index += 1
                }
                if index < lines.count, style.apply(comment: lines[index]) { index += 1 }
                if style != .plain { blocks[first].table = style }
                continue
            }
            blocks.append(parseLine(line))
            index += 1
        }
        if blocks.isEmpty {
            return [Block(type: .paragraph, spans: [InlineSpan(text: "")])]
        }
        return blocks
    }

    public static func serialize(_ blocks: [Block]) -> String {
        struct Piece {
            var text: String
            var list: BlockType?
        }
        var pieces: [Piece] = []
        var number = 0
        var tableColumns = 0
        var tableStyle = TableFormat.plain
        for (offset, block) in blocks.enumerated() {
            if block.type == .paragraph, block.plain.isEmpty { continue }
            if block.type == .tableRow {
                number = 0
                let first = offset == 0 || blocks[offset - 1].type != .tableRow
                if first {
                    var end = offset
                    while end < blocks.count, blocks[end].type == .tableRow { end += 1 }
                    tableColumns = blocks[offset..<end].map { tableCells($0.spans).count }.max() ?? 1
                    tableStyle = block.table ?? .plain
                }
                var cells = tableCells(block.spans).map(serializeCell)
                while cells.count < tableColumns { cells.append("") }
                var text = "| " + cells.joined(separator: " | ") + " |"
                if first {
                    text += "\n" + tableStyle.separator(columns: tableColumns)
                }
                let last = offset + 1 >= blocks.count || blocks[offset + 1].type != .tableRow
                if last, let comment = tableStyle.comment(columns: tableColumns) {
                    text += "\n" + comment
                }
                pieces.append(Piece(text: text, list: .tableRow))
                continue
            }
            let inline = serializeInline(block.spans)
            switch block.type {
            case .heading1:
                number = 0
                pieces.append(Piece(text: heading("#", inline), list: nil))
            case .heading2:
                number = 0
                pieces.append(Piece(text: heading("##", inline), list: nil))
            case .heading3:
                number = 0
                pieces.append(Piece(text: heading("###", inline), list: nil))
            case .bullet:
                number = 0
                pieces.append(Piece(text: "- \(inline)", list: .bullet))
            case .numbered:
                number += 1
                pieces.append(Piece(text: "\(number). \(inline)", list: .numbered))
            case .checkbox:
                number = 0
                let mark = block.checked ? "x" : " "
                pieces.append(Piece(text: "- [\(mark)] \(inline)", list: .checkbox))
            case .code:
                number = 0
                pieces.append(Piece(text: "```\(block.language)\n\(block.plain)\n```", list: nil))
            case .paragraph:
                number = 0
                pieces.append(Piece(text: inline, list: nil))
            case .excerpt:
                number = 0
                pieces.append(Piece(text: excerptLine(block), list: nil))
            case .tableRow:
                break
            }
        }
        guard !pieces.isEmpty else { return "" }
        var output = pieces[0].text
        for index in 1..<pieces.count {
            let sameList = pieces[index].list != nil && pieces[index].list == pieces[index - 1].list
            output += sameList ? "\n" : "\n\n"
            output += pieces[index].text
        }
        return output + "\n"
    }

    /// The blocks a text excerpt shows: the section under the first heading with this text, up to the next
    /// heading of the same or a higher level, heading included. Nil `heading` is the whole note; a heading
    /// that is gone yields nil. See ADR 0035.
    public static func section(of markdown: String, heading: String?) -> [Block]? {
        let blocks = parse(markdown)
        guard let heading else { return blocks }
        let wanted = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = blocks.firstIndex(where: { level(of: $0.type) != nil && $0.plain.trimmingCharacters(in: .whitespaces) == wanted }),
              let startLevel = level(of: blocks[start].type) else { return nil }
        var end = start + 1
        while end < blocks.count {
            if let next = level(of: blocks[end].type), next <= startLevel { break }
            end += 1
        }
        return Array(blocks[start..<end])
    }

    /// Headings of a note, in order, for choosing a section.
    public static func headings(in markdown: String) -> [String] {
        parse(markdown).filter { level(of: $0.type) != nil }
            .map { $0.plain.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func level(of type: BlockType) -> Int? {
        switch type {
        case .heading1: 1
        case .heading2: 2
        case .heading3: 3
        default: nil
        }
    }

    public static func title(for markdown: String) -> String {
        let blocks = parse(markdown)
        if let heading = blocks.first(where: { [.heading1, .heading2, .heading3].contains($0.type) }) {
            let text = heading.plain.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return clip(text) }
        }
        if let line = blocks.first(where: { $0.type != .excerpt && !$0.plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return clip(line.plain.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Note.untitled
    }

    public static func parseInline(_ source: String, cursorUTF16: Int? = nil) -> InlineParse {
        let cells = inlineCells(source)
        let spans = group(cells)
        let plain = spans.map(\.text).joined()
        let total = (plain as NSString).length
        let mapped = mapCursor(cursorUTF16, cells: cells, total: total)
        return InlineParse(spans: spans, plain: plain, cursorUTF16: mapped)
    }

    public static func serializeInline(_ spans: [InlineSpan]) -> String {
        var output = ""
        var index = 0
        let all = normalize(spans)
        while index < all.count {
            guard let link = all[index].link else {
                output += styled(all[index])
                index += 1
                continue
            }
            // Neighbouring spans with the same target are one link with styles inside.
            var label = ""
            while index < all.count, all[index].link == link {
                label += styled(all[index])
                index += 1
            }
            output += "[\(label)](\(link))"
        }
        return output
    }

    private static func styled(_ span: InlineSpan) -> String {
        let body = escape(span.text)
        if span.code { return "`\(body)`" }
        if span.bold, span.italic { return "***\(body)***" }
        if span.bold { return "**\(body)**" }
        if span.italic { return "*\(body)*" }
        return body
    }

    public static func split(_ block: Block, atUTF16 cursor: Int) -> (Block, Block) {
        let (leftSpans, rightSpans) = splitSpans(block.spans, atUTF16: cursor)
        let rightType: BlockType = switch block.type {
        case .bullet, .numbered, .checkbox, .code, .tableRow: block.type
        case .heading1, .heading2, .heading3, .paragraph, .excerpt: .paragraph
        }
        let left = Block(id: block.id, type: block.type, spans: leftSpans, checked: block.checked, language: block.language)
        let right = Block(type: rightType, spans: rightSpans, checked: false, language: block.language)
        return (left, right)
    }

    public static func droppingPrefix(_ spans: [InlineSpan], utf16 count: Int) -> [InlineSpan] {
        splitSpans(spans, atUTF16: count).1
    }

    public static func normalize(_ spans: [InlineSpan]) -> [InlineSpan] {
        var result: [InlineSpan] = []
        for span in spans where !span.text.isEmpty {
            if var last = result.last, last.sameStyle(as: span) {
                last.text += span.text
                result[result.count - 1] = last
            } else {
                result.append(span)
            }
        }
        if result.isEmpty { result = [InlineSpan(text: "")] }
        return result
    }

    /// Splits a table row's spans at the tab between cells. Always at least one cell.
    public static func tableCells(_ spans: [InlineSpan]) -> [[InlineSpan]] {
        var cells: [[InlineSpan]] = [[]]
        for span in spans {
            let parts = span.text.components(separatedBy: "\t")
            for (index, part) in parts.enumerated() {
                if index > 0 { cells.append([]) }
                if !part.isEmpty {
                    var piece = span
                    piece.text = part
                    cells[cells.count - 1].append(piece)
                }
            }
        }
        return cells
    }

    private static func serializeCell(_ spans: [InlineSpan]) -> String {
        serializeInline(spans.isEmpty ? [InlineSpan(text: "")] : spans)
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.count > 1
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    /// `| a | b |` → one block, cells joined by tabs. `\|` stays a literal bar inside a cell.
    private static func tableRow(_ line: String) -> Block {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                if character != "|" { current.append("\\") }
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current)
        var spans: [InlineSpan] = []
        for (index, cell) in cells.enumerated() {
            if index > 0 { spans.append(InlineSpan(text: "\t")) }
            spans.append(contentsOf: parseInline(cell.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "|", with: "\\|")).spans)
        }
        return Block(type: .tableRow, spans: spans)
    }

    private static func heading(_ marks: String, _ inline: String) -> String {
        inline.isEmpty ? marks : "\(marks) \(inline)"
    }

    private static func clip(_ text: String) -> String {
        (text.count <= 80 ? text : String(text.prefix(80))).clippedUTF16(Limits.title)
    }

    /// An excerpt block for `excerpt`. An empty label becomes `Ausschnitt`, because older versions
    /// would read `![](…)` as text and escape it. See ADR 0032.
    public static func excerptBlock(_ excerpt: Excerpt, label: String = "") -> Block {
        excerptBlock(.page(excerpt), label: label)
    }

    public static func excerptBlock(_ excerpt: ExcerptTarget, label: String = "") -> Block {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? Excerpt.defaultLabel : trimmed
        return Block(type: .excerpt, spans: [InlineSpan(text: text, link: excerpt.target)])
    }

    /// The excerpt a block shows, if it is one.
    public static func excerpt(in block: Block) -> ExcerptTarget? {
        guard block.type == .excerpt else { return nil }
        return block.spans.lazy.compactMap(\.link).compactMap(ExcerptTarget.init(target:)).first
    }

    /// The blocks of `markdown` a text excerpt shows, or nil if its section or anchors are gone.
    /// Excerpts inside are left out: a window does not show other windows. See ADR 0037.
    public static func blocks(for excerpt: TextExcerpt, in markdown: String) -> [Block]? {
        var blocks: [Block]
        if let section = excerpt.section {
            guard let found = Self.section(of: markdown, heading: section) else { return nil }
            blocks = found
        } else {
            blocks = parse(markdown)
        }
        if let from = excerpt.from {
            guard let start = blocks.firstIndex(where: { TextExcerpt.anchor($0.plain).hasPrefix(from) }) else { return nil }
            let to = excerpt.to ?? from
            guard let end = blocks[start...].firstIndex(where: { TextExcerpt.anchor($0.plain).hasPrefix(to) }) else { return nil }
            blocks = Array(blocks[start...end])
        }
        return blocks.filter { $0.type != .excerpt }
    }

    private static func excerptLine(_ block: Block) -> String {
        guard let excerpt = excerpt(in: block) else { return serializeInline(block.spans.map { InlineSpan(text: $0.text) }) }
        return "!" + serializeInline(excerptBlock(excerpt, label: block.plain).spans)
    }

    /// The whole line is `![label](target)` with an excerpt target.
    private static func excerptLine(_ line: String) -> Block? {
        guard line.hasPrefix("!") else { return nil }
        let ns = line as NSString
        guard let (label, target, length) = linkAt(ns, 1, ns.length), length == ns.length - 1,
              let excerpt = ExcerptTarget(target: target) else { return nil }
        return excerptBlock(excerpt, label: parseInline(label).plain)
    }

    private static func parseLine(_ line: String) -> Block {
        let trimmed = String(line.drop(while: \.isWhitespace))
        if let block = excerptLine(trimmed.trimmingCharacters(in: .whitespaces)) {
            return block
        }
        if let (type, content) = headingPrefix(trimmed) {
            return Block(type: type, spans: parseInline(content).spans)
        }
        if let (checked, content) = checkboxPrefix(trimmed) {
            return Block(type: .checkbox, spans: parseInline(content).spans, checked: checked)
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            return Block(type: .bullet, spans: parseInline(String(trimmed.dropFirst(2))).spans)
        }
        if let content = numberedPrefix(trimmed) {
            return Block(type: .numbered, spans: parseInline(content).spans)
        }
        return Block(type: .paragraph, spans: parseInline(trimmed).spans)
    }

    private static func headingPrefix(_ line: String) -> (BlockType, String)? {
        let marks = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(marks) else { return nil }
        let type: BlockType = switch marks {
        case 1: .heading1
        case 2: .heading2
        default: .heading3
        }
        let rest = line.dropFirst(marks)
        if rest.isEmpty { return (type, "") }
        guard rest.first == " " else { return nil }
        return (type, String(rest.dropFirst()))
    }

    private static func checkboxPrefix(_ line: String) -> (Bool, String)? {
        guard line.hasPrefix("- [") else { return nil }
        let ns = line as NSString
        guard ns.length >= 5 else { return nil }
        let mark = ns.substring(with: NSRange(location: 3, length: 1))
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        guard ns.length >= 6, ns.substring(with: NSRange(location: 4, length: 2)) == "] " || (ns.length == 5 && ns.substring(from: 4) == "]") else {
            if ns.length >= 5, ns.substring(from: 4) == "]" {
                return (mark != " ", "")
            }
            return nil
        }
        let content = ns.length > 6 ? ns.substring(from: 6) : ""
        return (mark != " ", content)
    }

    private static func numberedPrefix(_ line: String) -> String? {
        var index = line.startIndex
        var digits = 0
        while index < line.endIndex, line[index].isNumber {
            digits += 1
            index = line.index(after: index)
        }
        guard digits > 0, index < line.endIndex, line[index] == "." else { return nil }
        index = line.index(after: index)
        guard index < line.endIndex, line[index] == " " else { return nil }
        return String(line[line.index(after: index)...])
    }

    private struct Cell {
        var sourcePos: Int
        var text: String
        var bold: Bool
        var italic: Bool
        var code: Bool
        var link: String? = nil
    }

    private enum Mode {
        case plain, bold, italic, both, code

        var marker: String {
            switch self {
            case .plain: return ""
            case .bold: return "**"
            case .italic: return "*"
            case .both: return "***"
            case .code: return "`"
            }
        }

        var bold: Bool { self == .bold || self == .both }
        var italic: Bool { self == .italic || self == .both }
        var code: Bool { self == .code }
    }

    private static func inlineCells(_ source: String) -> [Cell] {
        let ns = source as NSString
        let count = ns.length
        var committed: [Cell] = []
        var pending: [Cell] = []
        var mode = Mode.plain
        var markerSource = 0
        var index = 0

        func addText(_ text: String, source: Int) {
            let cell = Cell(sourcePos: source, text: text, bold: mode.bold, italic: mode.italic, code: mode.code)
            if mode == .plain {
                committed.append(cell)
            } else {
                pending.append(cell)
            }
        }

        func emitLiteral(_ marker: String, at position: Int) {
            var cursor = position
            for character in marker {
                let text = String(character)
                committed.append(Cell(sourcePos: cursor, text: text, bold: false, italic: false, code: false))
                cursor += text.utf16.count
            }
        }

        func close() {
            if pending.isEmpty {
                emitLiteral(mode.marker, at: markerSource)
            } else {
                committed.append(contentsOf: pending)
            }
            pending.removeAll()
            mode = .plain
        }

        func open(_ next: Mode, at position: Int) {
            mode = next
            markerSource = position
            pending.removeAll()
        }

        while index < count {
            if starts(ns, index, count, "\\"), index + 1 < count {
                let (text, length) = readChar(ns, index + 1, count)
                addText(text, source: index)
                index += 1 + length
                continue
            }
            if mode == .code {
                if starts(ns, index, count, "`") {
                    close()
                    index += 1
                } else {
                    let (text, length) = readChar(ns, index, count)
                    addText(text, source: index)
                    index += length
                }
                continue
            }
            if mode == .plain {
                if let (label, target, length) = linkAt(ns, index, count) {
                    for cell in inlineCells(label) {
                        var linked = cell
                        linked.sourcePos += index + 1
                        linked.link = target
                        committed.append(linked)
                    }
                    index += length
                    continue
                }
                if starts(ns, index, count, "***") {
                    open(.both, at: index)
                    index += 3
                    continue
                }
                if starts(ns, index, count, "**") {
                    open(.bold, at: index)
                    index += 2
                    continue
                }
                if starts(ns, index, count, "*") {
                    open(.italic, at: index)
                    index += 1
                    continue
                }
                if starts(ns, index, count, "`") {
                    open(.code, at: index)
                    index += 1
                    continue
                }
                let (text, length) = readChar(ns, index, count)
                addText(text, source: index)
                index += length
                continue
            }
            if starts(ns, index, count, mode.marker) {
                let closer = mode.marker
                close()
                index += (closer as NSString).length
                continue
            }
            let (text, length) = readChar(ns, index, count)
            addText(text, source: index)
            index += length
        }
        if mode != .plain {
            let marker = mode.marker
            emitLiteral(marker, at: markerSource)
            for cell in pending {
                committed.append(Cell(sourcePos: cell.sourcePos, text: cell.text, bold: false, italic: false, code: false))
            }
        }
        return committed
    }

    private static func group(_ cells: [Cell]) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        for cell in cells {
            let span = InlineSpan(text: cell.text, bold: cell.bold, italic: cell.italic, code: cell.code, link: cell.link)
            if var last = spans.last, last.sameStyle(as: span) {
                last.text += cell.text
                spans[spans.count - 1] = last
            } else {
                spans.append(span)
            }
        }
        return normalize(spans)
    }

    /// `[label](target)` starting at `index`: label without `]`, target without spaces, both unescaped
    /// and on one line. An empty label or target is no link. Returns the source length consumed.
    private static func linkAt(_ ns: NSString, _ index: Int, _ count: Int) -> (String, String, Int)? {
        guard starts(ns, index, count, "[") else { return nil }
        var cursor = index + 1
        var labelEnd: Int?
        while cursor < count {
            let unit = ns.character(at: cursor)
            if unit == 0x5C { cursor += 2; continue } // backslash escapes the next unit
            if unit == 0x5B { return nil } // `[` inside a label: not a link
            if unit == 0x5D { labelEnd = cursor; break } // `]`
            cursor += 1
        }
        guard let labelEnd, labelEnd > index + 1, starts(ns, labelEnd + 1, count, "(") else { return nil }
        let targetStart = labelEnd + 2
        cursor = targetStart
        while cursor < count {
            let unit = ns.character(at: cursor)
            if unit == 0x29 { break } // `)`
            if unit == 0x20 || unit == 0x28 { return nil } // space or `(` in a target: not a link
            cursor += 1
        }
        guard cursor < count, cursor > targetStart else { return nil }
        let label = ns.substring(with: NSRange(location: index + 1, length: labelEnd - index - 1))
        let target = ns.substring(with: NSRange(location: targetStart, length: cursor - targetStart))
        return (label, target, cursor + 1 - index)
    }

    private static func mapCursor(_ cursor: Int?, cells: [Cell], total: Int) -> Int {
        guard let cursor else { return total }
        if cursor <= 0 { return 0 }
        var output = 0
        for cell in cells {
            if cursor <= cell.sourcePos { return output }
            output += (cell.text as NSString).length
        }
        return output
    }

    private static func splitSpans(_ spans: [InlineSpan], atUTF16 cursor: Int) -> ([InlineSpan], [InlineSpan]) {
        var left: [InlineSpan] = []
        var right: [InlineSpan] = []
        var seen = 0
        var didSplit = false
        for span in normalize(spans) {
            if didSplit {
                right.append(span)
                continue
            }
            let length = (span.text as NSString).length
            if cursor <= seen {
                didSplit = true
                right.append(span)
                continue
            }
            if cursor >= seen + length {
                left.append(span)
                seen += length
                continue
            }
            let offset = cursor - seen
            let ns = span.text as NSString
            let head = ns.substring(to: offset)
            let tail = ns.substring(from: offset)
            if !head.isEmpty {
                var part = span
                part.text = head
                left.append(part)
            }
            if !tail.isEmpty {
                var part = span
                part.text = tail
                right.append(part)
            }
            didSplit = true
        }
        return (normalize(left), normalize(right))
    }

    /// `[` only needs a backslash where a link could start, so plain brackets stay readable.
    private static func escape(_ text: String) -> String {
        var output = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if character == "\\" || character == "*" || character == "`" {
                output.append("\\")
            } else if character == "[", String(characters[(index + 1)...]).contains("](") {
                output.append("\\")
            }
            output.append(character)
        }
        return output
    }

    private static func starts(_ ns: NSString, _ index: Int, _ count: Int, _ token: String) -> Bool {
        let length = (token as NSString).length
        guard index + length <= count else { return false }
        return ns.substring(with: NSRange(location: index, length: length)) == token
    }

    private static func readChar(_ ns: NSString, _ index: Int, _ count: Int) -> (String, Int) {
        let unit = ns.character(at: index)
        if unit >= 0xD800, unit <= 0xDBFF, index + 1 < count {
            return (ns.substring(with: NSRange(location: index, length: 2)), 2)
        }
        return (ns.substring(with: NSRange(location: index, length: 1)), 1)
    }
}
