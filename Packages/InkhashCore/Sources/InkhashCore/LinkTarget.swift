import Foundation

/// What a typed link target becomes before it is stored, in text and on pages alike. The server
/// accepts only `https://`, `http://`, `mailto:` and `inkhash://note/` (API.md), and the Markdown
/// codec cannot carry spaces or parentheses in a target. See ADR 0031.
public enum LinkTarget {
    public static let maxLength = 2000

    /// The stored form of `input`, or nil if it cannot be a link.
    /// - `example.com/a` becomes `https://example.com/a`
    /// - `name@example.com` becomes `mailto:name@example.com`
    /// - note links are written with a lowercase ID
    /// - other schemes, inner whitespace and empty input are rejected
    /// - `(` and `)` are escaped unless `escapingParentheses` is false; pages need no escaping
    public static func normalize(_ input: String, escapingParentheses: Bool = true) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let lower = trimmed.lowercased()
        let result: String
        if lower.hasPrefix(NoteLink.prefix) {
            guard let id = NoteLink.noteID(in: trimmed) else { return nil }
            result = NoteLink.target(for: id)
        } else if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            let scheme = lower.hasPrefix("https://") ? "https://" : "http://"
            let rest = trimmed.dropFirst(scheme.count)
            guard !rest.isEmpty else { return nil }
            result = scheme + rest
        } else if lower.hasPrefix("mailto:") {
            let rest = trimmed.dropFirst("mailto:".count)
            guard !rest.isEmpty else { return nil }
            result = "mailto:" + rest
        } else if trimmed.contains("://") || hasOtherScheme(trimmed) {
            return nil
        } else if trimmed.contains("@"), !trimmed.contains("/") {
            result = "mailto:" + trimmed
        } else {
            guard trimmed.contains("."), !trimmed.hasPrefix("."), !trimmed.hasPrefix("/") else { return nil }
            result = "https://" + trimmed
        }
        let escaped = escapingParentheses
            ? result.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
            : result
        return escaped.count <= maxLength ? escaped : nil
    }

    /// The server's check for element links, see API.md.
    public static func isAccepted(_ target: String) -> Bool {
        target.count <= maxLength && ["https://", "http://", "mailto:", NoteLink.prefix].contains { target.hasPrefix($0) }
    }

    /// A stored target the server would refuse, as written by older versions, repaired where possible.
    public static func repaired(_ target: String) -> String? {
        isAccepted(target) ? target : normalize(target, escapingParentheses: false)
    }

    /// True if `input` would be stored as a web or mail address rather than read as a note title.
    public static func looksLikeAddress(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespaces) == nil else { return false }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:")
            || trimmed.contains("://") || trimmed.contains("@") || trimmed.contains(".")
    }

    /// A short label for a target nobody named: the host of a web address, the address of a mail link.
    public static func defaultLabel(for target: String) -> String {
        if target.lowercased().hasPrefix("mailto:") {
            return String(target.dropFirst("mailto:".count))
        }
        if let host = URL(string: target)?.host(), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return target
    }

    /// `tel:123`, `javascript:x`: a scheme before the first colon. A port as in `host:8080` is not one.
    private static func hasOtherScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let scheme = text[..<colon]
        let after = text[text.index(after: colon)...]
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else { return false }
        // `example.com:8080/x` has a port, not a scheme.
        if scheme.contains("."), after.first?.isNumber == true { return false }
        return true
    }
}
