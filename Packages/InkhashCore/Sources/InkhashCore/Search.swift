import Foundation

public struct SearchDocument: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var body: String
    public var tags: [String]

    public init(id: UUID, title: String, body: String, tags: [String]) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
    }
}

public struct SearchHit: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var score: Int
    public var snippet: String

    public init(id: UUID, score: Int, snippet: String) {
        self.id = id
        self.score = score
        self.snippet = snippet
    }
}

/// Tolerant search over titles, text, handwriting transcripts, and tags.
/// Every query word must match somewhere. Order does not matter.
/// Matching allows case, diacritics, `ß`/`ss`, a prefix of three or more characters,
/// and a small edit distance so recognition errors still hit.
/// It does not expand synonyms.
public enum NoteSearch {
    public static func search(_ query: String, in documents: [SearchDocument]) -> [SearchHit] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for document in documents {
            if let hit = match(tokens, document: document, rawQuery: query) {
                hits.append(hit)
            }
        }
        return hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public static func normalize(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
    }

    private struct Field {
        var weight: Int
        var tokens: [String]
        var rawLines: [String]
    }

    private static func match(_ queryTokens: [String], document: SearchDocument, rawQuery: String) -> SearchHit? {
        let fields = [
            Field(weight: 5, tokens: document.tags.flatMap(tokenize), rawLines: document.tags.map { "#\($0)" }),
            Field(weight: 4, tokens: tokenize(document.title), rawLines: [document.title]),
            Field(weight: 2, tokens: tokenize(document.body), rawLines: document.body.components(separatedBy: .newlines)),
        ]
        var score = 0
        for query in queryTokens {
            var best = 0
            for field in fields {
                for token in field.tokens {
                    best = max(best, compare(query, token) * field.weight)
                }
            }
            if best == 0 { return nil }
            score += best
        }
        return SearchHit(id: document.id, score: score, snippet: snippet(queryTokens, document: document, fallback: rawQuery))
    }

    private static func compare(_ query: String, _ token: String) -> Int {
        if query == token { return 3 }
        if query.count >= 3, token.hasPrefix(query) { return 2 }
        let limit = fuzzyLimit(query.count)
        guard limit > 0, abs(query.count - token.count) <= limit else { return 0 }
        guard levenshtein(query, token, limit: limit) <= limit else { return 0 }
        return 1
    }

    private static func fuzzyLimit(_ count: Int) -> Int {
        if count <= 3 { return 0 }
        if count <= 6 { return 1 }
        return 2
    }

    private static func tokenize(_ text: String) -> [String] {
        let normalized = normalize(text)
        var tokens: [String] = []
        var current = ""
        for character in normalized {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func snippet(_ queryTokens: [String], document: SearchDocument, fallback: String) -> String {
        let lines = ([document.title] + document.body.components(separatedBy: .newlines) + document.tags.map { "#\($0)" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var bestLine = ""
        var bestScore = -1
        for line in lines {
            let tokens = tokenize(line)
            var covered = 0
            for query in queryTokens where tokens.contains(where: { compare(query, $0) > 0 }) {
                covered += 1
            }
            if covered > bestScore {
                bestScore = covered
                bestLine = line
            }
        }
        let chosen = bestLine.isEmpty ? fallback : bestLine
        if chosen.count <= 90 { return chosen }
        return String(chosen.prefix(90))
    }

    private static func levenshtein(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i]
            var rowMin = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                let value = min(
                    current[j - 1] + 1,
                    previous[j] + 1,
                    previous[j - 1] + cost
                )
                current.append(value)
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }
}
