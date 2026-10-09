import Foundation
import InkhashCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Tables in the editor: rows as paragraphs, columns as tab stops. See ADR 0027 and 0036.
extension EditorEngine {
    var hasTables: Bool {
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
        let column = TableSyntax.column(before: before)
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
        TableSyntax.cellCount(ns.substring(with: content(of: row)))
    }

    /// Equal columns across the text width, as tab stops. The layout manager draws the grid on them.
    func layoutTable(around location: Int, width: CGFloat? = nil) {
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

    func layoutTables(width: CGFloat? = nil) {
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
    func nextCell() {
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
    func tableNewline(_ row: NSRange, atEnd: Bool = false) {
        let text = ns.substring(with: content(of: row))
        if TableSyntax.isEmptyRow(text), !atEnd {
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
        let empty = TableSyntax.emptyRow(columns: columns)
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
    func startTable(_ current: NSRange) -> Bool {
        guard let cells = TableSyntax.headerCells(ns.substring(with: content(of: current))) else { return false }
        let style = BlockStyle(type: .tableRow)
        let header = NoteDocument.paragraph(
            MarkdownCodec.parseInline(cells.joined(separator: "\t")).spans, style: style, newline: false
        )
        let contentRange = content(of: current)
        edit(contentRange, replacement: header.string) { host.storage.replaceCharacters(in: contentRange, with: header) }
        tableNewline(paragraph(at: current.location), atEnd: true)
        return true
    }
}
