import Foundation

/// How a table looks beyond its cells. Alignment is plain Markdown (`:---:`); widths, the header switch
/// and zebra rows live in a comment line right after the table, which other Markdown readers hide.
/// Carried by the first row of a table. See ADR 0036.
public struct TableFormat: Equatable, Sendable {
    public enum Alignment: String, Sendable, CaseIterable {
        case left, center, right
    }

    /// Per column; missing columns are left.
    public var alignments: [Alignment]
    /// Per column, as shares of the width. Empty means equal columns.
    public var widths: [Double]
    /// False shows the first row like any other.
    public var header: Bool
    public var zebra: Bool

    public init(alignments: [Alignment] = [], widths: [Double] = [], header: Bool = true, zebra: Bool = false) {
        self.alignments = alignments
        self.widths = widths
        self.header = header
        self.zebra = zebra
    }

    public static let plain = TableFormat()

    /// Sets one column's alignment; an all-left table stores none.
    public mutating func setAlignment(_ alignment: Alignment, of column: Int, columns: Int) {
        var next = (0..<max(columns, column + 1)).map { self.alignment(of: $0) }
        next[column] = alignment
        alignments = next.allSatisfy { $0 == .left } ? [] : next
    }

    public func alignment(of column: Int) -> Alignment {
        alignments.indices.contains(column) ? alignments[column] : .left
    }

    /// Shares for `columns` columns, summing to 1. Equal unless widths were set for exactly these columns.
    public func shares(columns: Int) -> [Double] {
        let count = max(columns, 1)
        guard widths.count == count, widths.allSatisfy({ $0 > 0 }) else {
            return Array(repeating: 1 / Double(count), count: count)
        }
        let total = widths.reduce(0, +)
        return widths.map { $0 / total }
    }

    /// Makes `column` wider by `step` (a share; negative narrows), taking it evenly from the others.
    /// No column gets narrower than 8 %.
    public func resizing(column: Int, by step: Double, columns: Int) -> TableFormat {
        var shares = shares(columns: columns)
        guard shares.indices.contains(column), columns > 1 else { return self }
        let minimum = 0.08
        let target = min(max(shares[column] + step, minimum), 1 - minimum * Double(columns - 1))
        let delta = target - shares[column]
        let others = shares.indices.filter { $0 != column }
        let room = others.map { shares[$0] - minimum }.reduce(0, +)
        guard delta < 0 || room > 0 else { return self }
        for index in others {
            let part = delta > 0 ? (shares[index] - minimum) / room : 1 / Double(others.count)
            shares[index] -= delta * part
        }
        shares[column] = target
        var next = self
        next.widths = shares.map { ($0 * 100).rounded() / 100 }
        return next
    }

    // MARK: Markdown

    /// `| --- | :---: | ---: |` for this many columns.
    func separator(columns: Int) -> String {
        let cells = (0..<max(columns, 1)).map { column -> String in
            switch alignment(of: column) {
            case .left: "---"
            case .center: ":---:"
            case .right: "---:"
            }
        }
        return "| " + cells.joined(separator: " | ") + " |"
    }

    /// Reads alignments from a separator line. `:---` is left like `---`.
    static func alignments(fromSeparator line: String) -> [Alignment] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let result = cells.map { cell -> Alignment in
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":") && cell.count > 1
            if left, right { return .center }
            if right { return .right }
            return .left
        }
        return result.allSatisfy { $0 == .left } ? [] : result
    }

    static let commentPrefix = "<!-- inkhash:table"

    /// The comment line for what Markdown cannot say, or nil if there is nothing to say.
    func comment(columns: Int) -> String? {
        var parts: [String] = []
        let shares = shares(columns: columns)
        let equal = 1 / Double(max(columns, 1))
        if shares.contains(where: { abs($0 - equal) > 0.005 }) {
            parts.append("widths=" + shares.map { String(Int(($0 * 100).rounded())) }.joined(separator: ","))
        }
        if !header { parts.append("header=off") }
        if zebra { parts.append("zebra") }
        guard !parts.isEmpty else { return nil }
        return "\(Self.commentPrefix) \(parts.joined(separator: " ")) -->"
    }

    /// Applies a comment line. Unknown words are ignored, so later versions can add some.
    mutating func apply(comment line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(Self.commentPrefix), trimmed.hasSuffix("-->") else { return false }
        let body = trimmed.dropFirst(Self.commentPrefix.count).dropLast(3)
        for word in body.split(separator: " ") {
            if word == "header=off" { header = false }
            if word == "zebra" { zebra = true }
            if word.hasPrefix("widths=") {
                let values = word.dropFirst("widths=".count).split(separator: ",").compactMap { Double($0) }
                if values.allSatisfy({ $0 > 0 }), !values.isEmpty { widths = values }
            }
        }
        return true
    }
}
