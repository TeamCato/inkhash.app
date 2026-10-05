import Foundation

public enum TagMode: Sendable {
    /// `# Titel` and `##` at the start of a line are headings. `#wort` is a tag.
    case markdown
    /// A hash glued to a word, or a hash with spaces before the word, is a tag.
    case handwriting
}

public struct RecognizedWord: Equatable, Sendable {
    public var text: String
    /// Normalized coordinates, origin at the top left, each axis in 0...1.
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(text: String, minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.text = text
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

public enum Hashtags {
    public static func inText(_ text: String, mode: TagMode) -> [String] {
        var found: [String] = []
        for line in text.components(separatedBy: .newlines) {
            scan(line: line, mode: mode, into: &found)
        }
        return unique(found)
    }

    public static func transcript(from words: [RecognizedWord]) -> String {
        let sorted = words.sorted { lhs, rhs in
            if abs(lhs.minY - rhs.minY) > 0.000_1 { return lhs.minY < rhs.minY }
            return lhs.minX < rhs.minX
        }
        var lines: [[RecognizedWord]] = []
        for word in sorted {
            if var last = lines.last, belongsOnSameLine(last, word) {
                last.append(word)
                lines[lines.count - 1] = last
            } else {
                lines.append([word])
            }
        }
        return lines.map { line in
            line.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }.joined(separator: "\n")
    }

    public static func inObservations(_ words: [RecognizedWord]) -> [String] {
        var found = inText(transcript(from: words), mode: .handwriting)
        found.append(contentsOf: tagsBesideHashMarks(words))
        return unique(found)
    }

    public static func unique(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            guard let canonical = canonicalize(tag), seen.insert(canonical).inserted else { continue }
            result.append(canonical)
            // The server takes at most 50; the first ones win.
            if result.count == Limits.tagsPerNote { break }
        }
        return result
    }

    public static func canonicalize(_ tag: String) -> String? {
        var word = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        while word.hasPrefix("#") || word.hasPrefix("♯") || word.hasPrefix("＃") {
            word.removeFirst()
        }
        word = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "de_DE"))
        guard !word.isEmpty, word.utf16.count <= Limits.tagLength else { return nil }
        guard word.allSatisfy(isTagCharacter) else { return nil }
        guard let first = word.first, first.isLetter || first.isNumber else { return nil }
        return word
    }

    private static func scan(line: String, mode: TagMode, into found: inout [String]) {
        let chars = Array(line)
        var index = 0
        var atLineStart = true
        var previous: Character?
        while index < chars.count {
            let character = chars[index]
            if character.isWhitespace {
                previous = character
                index += 1
                continue
            }
            if character == "#" || character == "♯" || character == "＃" {
                if previous?.isLetter == true || previous?.isNumber == true {
                    previous = character
                    atLineStart = false
                    index += 1
                    continue
                }
                var hashes = 0
                let mark = character
                while index < chars.count, chars[index] == mark {
                    hashes += 1
                    index += 1
                }
                let spaceAfter = index < chars.count && chars[index].isWhitespace
                if mode == .markdown, atLineStart, (hashes > 1 || spaceAfter) {
                    atLineStart = false
                    previous = nil
                    continue
                }
                if mode == .handwriting {
                    var cursor = index
                    while cursor < chars.count, chars[cursor].isWhitespace {
                        cursor += 1
                    }
                    if let tag = readTag(chars, from: &cursor), let canonical = canonicalize(tag) {
                        found.append(canonical)
                        index = cursor
                        atLineStart = false
                        previous = chars[index - 1]
                        continue
                    }
                }
                if let tag = readTag(chars, from: &index), let canonical = canonicalize(tag) {
                    found.append(canonical)
                    atLineStart = false
                    previous = index > 0 ? chars[index - 1] : nil
                    continue
                }
                atLineStart = false
                previous = nil
                continue
            }
            atLineStart = false
            previous = character
            index += 1
        }
    }

    private static func readTag(_ chars: [Character], from index: inout Int) -> String? {
        guard index < chars.count else { return nil }
        let start = index
        guard chars[index].isLetter || chars[index].isNumber else { return nil }
        index += 1
        while index < chars.count {
            let character = chars[index]
            if isTagCharacter(character) {
                index += 1
            } else {
                break
            }
        }
        let word = String(chars[start..<index])
        guard word.utf16.count <= Limits.tagLength else { return nil }
        return word
    }

    private static func isTagCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    private static func isHashToken(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { $0 == "#" || $0 == "♯" || $0 == "＃" }
    }

    private static func tagsBesideHashMarks(_ words: [RecognizedWord]) -> [String] {
        var found: [String] = []
        for hash in words where isHashToken(hash.text) {
            guard let neighbor = nearestWord(toTheRightOf: hash, in: words) else { continue }
            if let tag = plainToken(neighbor.text), let canonical = canonicalize(tag) {
                found.append(canonical)
            }
            found.append(contentsOf: inText(neighbor.text, mode: .handwriting))
        }
        return found
    }

    private static func plainToken(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first.isLetter || first.isNumber else { return nil }
        guard trimmed.allSatisfy(isTagCharacter), trimmed.utf16.count <= Limits.tagLength else { return nil }
        return trimmed
    }

    private static func nearestWord(toTheRightOf hash: RecognizedWord, in words: [RecognizedWord]) -> RecognizedWord? {
        let hashWidth = max(hash.maxX - hash.minX, 0.01)
        let limit = max(0.06, hashWidth * 4)
        var best: RecognizedWord?
        var bestGap = Double.greatestFiniteMagnitude
        for word in words {
            if isHashToken(word.text) { continue }
            let gap = word.minX - hash.maxX
            guard gap >= -0.01, gap < limit else { continue }
            guard verticalOverlap(hash, word) >= 0.4 else { continue }
            if gap < bestGap {
                bestGap = gap
                best = word
            }
        }
        return best
    }

    private static func belongsOnSameLine(_ line: [RecognizedWord], _ word: RecognizedWord) -> Bool {
        guard verticalOverlap(lastUnion(line), word) >= 0.45 else { return false }
        let closest = line.map { other in
            if word.minX >= other.maxX { return word.minX - other.maxX }
            if other.minX >= word.maxX { return other.minX - word.maxX }
            return 0.0
        }.min() ?? 0
        return closest < 0.08
    }

    private static func verticalOverlap(_ lhs: RecognizedWord, _ rhs: RecognizedWord) -> Double {
        let top = max(lhs.minY, rhs.minY)
        let bottom = min(lhs.maxY, rhs.maxY)
        let overlap = bottom - top
        let minHeight = min(lhs.maxY - lhs.minY, rhs.maxY - rhs.minY)
        guard minHeight > 0, overlap > 0 else { return 0 }
        return overlap / minHeight
    }

    private static func lastUnion(_ line: [RecognizedWord]) -> RecognizedWord {
        let minX = line.map(\.minX).min() ?? 0
        let minY = line.map(\.minY).min() ?? 0
        let maxX = line.map(\.maxX).max() ?? 0
        let maxY = line.map(\.maxY).max() ?? 0
        return RecognizedWord(text: "", minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}
