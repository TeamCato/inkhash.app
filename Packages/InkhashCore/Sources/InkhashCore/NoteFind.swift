import Foundation

/// Finding a word in the text of the open note: every place it stands and which one is current. See ADR 0084.
/// Unlike the library search it matches the literal text, only case and accents are ignored.
public struct NoteFind: Equatable, Sendable {
    public private(set) var query: String
    /// Where the query stands, in UTF-16 offsets of the text, in reading order. Never overlapping.
    public private(set) var matches: [NSRange] = []
    /// Index into `matches`; nil while nothing matches.
    public private(set) var current: Int?

    public init(query: String = "") {
        self.query = query
    }

    public var currentRange: NSRange? { current.map { matches[$0] } }

    public static func ranges(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty, !query.allSatisfy(\.isWhitespace) else { return [] }
        let ns = text as NSString
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let locale = Locale(identifier: "de_DE")
        var found: [NSRange] = []
        var start = 0
        while start < ns.length {
            let range = ns.range(of: query, options: options, range: NSRange(location: start, length: ns.length - start), locale: locale)
            guard range.location != NSNotFound, range.length > 0 else { break }
            found.append(range)
            start = NSMaxRange(range)
        }
        return found
    }

    /// Searches `text` again for `query`. The current match is the first one at or after `anchor`,
    /// so typing on keeps the place and a changed text keeps it where it can.
    public mutating func update(query: String, in text: String, anchor: Int) {
        self.query = query
        matches = Self.ranges(of: query, in: text)
        guard !matches.isEmpty else {
            current = nil
            return
        }
        current = matches.firstIndex { $0.location >= anchor } ?? 0
    }

    /// The next match, after the last one the first again.
    public mutating func next() {
        guard let current, !matches.isEmpty else { return }
        self.current = (current + 1) % matches.count
    }

    /// The previous match, before the first one the last again.
    public mutating func previous() {
        guard let current, !matches.isEmpty else { return }
        self.current = (current + matches.count - 1) % matches.count
    }

    /// „2 von 5“, empty without a query.
    public var countLabel: String {
        guard !query.isEmpty else { return "" }
        guard let current else { return "Keine Treffer" }
        return "\(current + 1) von \(matches.count)"
    }
}
