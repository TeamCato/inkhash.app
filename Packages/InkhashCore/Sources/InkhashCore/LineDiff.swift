import Foundation

/// Lines of two texts side by side: which lines both have and which only one has.
/// For showing a conflict, not for merging. See ADR 0049.
public enum LineDiff {
    public enum Side: Equatable, Sendable {
        case both
        case left
        case right
    }

    public struct Line: Equatable, Sendable {
        public var text: String
        public var side: Side

        public init(_ text: String, _ side: Side) {
            self.text = text
            self.side = side
        }
    }

    /// Above this many lines on each side the table would be too big; every line counts as changed.
    public static let limit = 4000

    /// Lines in reading order, from the longest common subsequence of both texts.
    public static func compare(_ left: String, _ right: String) -> [Line] {
        let a = lines(left)
        let b = lines(right)
        if a.count > limit || b.count > limit {
            return a.map { Line($0, .left) } + b.map { Line($0, .right) }
        }
        // lengths[i][j]: common lines of a[i...] and b[j...].
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var result: [Line] = []
        var i = 0
        var j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                result.append(Line(a[i], .both))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                result.append(Line(a[i], .left))
                i += 1
            } else {
                result.append(Line(b[j], .right))
                j += 1
            }
        }
        result += a[i...].map { Line($0, .left) }
        result += b[j...].map { Line($0, .right) }
        return result
    }

    /// A trailing newline ends the last line; it does not start an empty one.
    static func lines(_ text: String) -> [String] {
        var parts = text.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        return parts
    }
}
