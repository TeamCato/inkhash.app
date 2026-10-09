import Foundation

/// Text rules of tables in the editor, where a row is a paragraph with its cells between tabs.
/// See ADR 0027 and 0036.
public enum TableSyntax {
    /// The cells of a typed `| a | b |` line that starts a table, or nil for any other line.
    public static func headerCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.filter({ $0 == "|" }).count >= 2 else { return nil }
        var inner = trimmed.dropFirst()
        if inner.hasSuffix("|") { inner = inner.dropLast() }
        let cells = inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        return cells.isEmpty ? nil : cells
    }

    /// How many cells a row's text holds.
    public static func cellCount(_ row: String) -> Int {
        row.components(separatedBy: "\t").count
    }

    /// The column of a cursor after `before`, the row's text up to it.
    public static func column(before: String) -> Int {
        before.filter { $0 == "\t" }.count
    }

    /// A row with nothing but separators: Return on it leaves the table.
    public static func isEmptyRow(_ row: String) -> Bool {
        row.trimmingCharacters(in: CharacterSet(charactersIn: "\t ")).isEmpty
    }

    /// The text of a new empty row with `columns` cells.
    public static func emptyRow(columns: Int) -> String {
        String(repeating: "\t", count: max(1, columns) - 1)
    }
}
