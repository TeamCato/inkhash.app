import Foundation

/// File and folder names for exported notes: readable, safe on every file system, unique.
/// See ADR 0051.
public enum ExportNames {
    /// Longest name part, in characters, before the extension.
    public static let maxLength = 80

    /// A title as a file name: no path separators, no characters Windows or macOS refuse,
    /// no leading dot, never empty.
    public static func fileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        var cleaned = String(String.UnicodeScalarView(title.unicodeScalars.map { forbidden.contains($0) ? " " : $0 }))
        cleaned = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        while cleaned.hasSuffix(".") { cleaned.removeLast() }
        return cleaned.isEmpty ? Note.untitled : cleaned
    }

    /// A note's folder path as a relative directory, each segment cleaned like a file name.
    public static func folderPath(_ folder: String) -> String {
        folder.split(separator: "/").map { fileName(String($0)) }.joined(separator: "/")
    }

    /// Hands out paths, numbering a name that is taken: `Plan.md`, `Plan 2.md`. Case does not
    /// count, since macOS and Windows file systems ignore it.
    public struct Namer {
        private var taken: Set<String> = []

        public init() {}

        public mutating func path(in directory: String, name: String, ext: String) -> String {
            let prefix = directory.isEmpty ? "" : directory + "/"
            var number = 1
            while true {
                let candidate = prefix + (number == 1 ? name : "\(name) \(number)") + "." + ext
                if taken.insert(candidate.lowercased()).inserted { return candidate }
                number += 1
            }
        }
    }
}
