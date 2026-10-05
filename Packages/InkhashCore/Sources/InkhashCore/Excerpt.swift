import Foundation

/// A window onto a rectangle of a handwriting page, shown inside a text note. Only this reference
/// is stored; the content is drawn from the source note when shown. See ADR 0032.
public struct Excerpt: Equatable, Sendable {
    public static let defaultLabel = "Ausschnitt"

    public var noteID: UUID
    public var pageID: UUID
    /// In page coordinates, like the strokes.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    /// Nil unless the rectangle has a positive, finite size and a non-negative, finite origin.
    public init?(noteID: UUID, pageID: UUID, x: Double, y: Double, width: Double, height: Double) {
        guard [x, y, width, height].allSatisfy(\.isFinite), x >= 0, y >= 0, width > 0, height > 0 else { return nil }
        self.noteID = noteID
        self.pageID = pageID
        self.x = Self.rounded(x)
        self.y = Self.rounded(y)
        self.width = Self.rounded(width)
        self.height = Self.rounded(height)
        guard self.width > 0, self.height > 0 else { return nil }
    }

    /// Reads `inkhash://note/<noteID>/page/<pageID>?rect=x,y,w,h`. Anything else is nil, including
    /// a plain note link.
    public init?(target: String) {
        guard target.lowercased().hasPrefix(NoteLink.prefix) else { return nil }
        let rest = String(target.dropFirst(NoteLink.prefix.count))
        guard let query = rest.range(of: "?rect=") else { return nil }
        let path = rest[..<query.lowerBound].split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 3, path[1] == "page",
              let noteID = UUID(uuidString: String(path[0])),
              let pageID = UUID(uuidString: String(path[2])) else { return nil }
        let numbers = rest[query.upperBound...].split(separator: ",", omittingEmptySubsequences: false)
        guard numbers.count == 4 else { return nil }
        let values = numbers.compactMap { Double($0) }
        guard values.count == 4 else { return nil }
        self.init(noteID: noteID, pageID: pageID, x: values[0], y: values[1], width: values[2], height: values[3])
    }

    public var target: String {
        let rect = [x, y, width, height].map(Self.format).joined(separator: ",")
        return "\(NoteLink.target(for: noteID))/page/\(pageID.uuidString.lowercased())?rect=\(rect)"
    }

    /// The rectangle cut to a page of this size, or nil if nothing of it lies on the page.
    public func clipped(toWidth pageWidth: Double, height pageHeight: Double) -> Excerpt? {
        let right = min(x + width, pageWidth)
        let bottom = min(y + height, pageHeight)
        return Excerpt(noteID: noteID, pageID: pageID, x: x, y: y, width: right - x, height: bottom - y)
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// At most two decimals with a point, no trailing zeros: `12`, `12.5`, `12.25`.
    private static func format(_ value: Double) -> String {
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

/// A window onto a text note: all of it, the section under a heading, or the paragraphs from one to
/// another, found by how they begin. See ADR 0037.
public struct TextExcerpt: Equatable, Sendable {
    /// How much of a paragraph's beginning identifies it.
    public static let anchorLength = 60

    public var noteID: UUID
    public var section: String?
    public var from: String?
    public var to: String?

    public init(noteID: UUID, section: String? = nil, from: String? = nil, to: String? = nil) {
        self.noteID = noteID
        self.section = Self.clean(section)
        self.from = Self.clean(from).map(Self.anchor)
        self.to = Self.clean(to).map(Self.anchor) ?? self.from
    }

    /// `inkhash://note/<id>?text`, then `&section=…` or `&from=…&to=…`, percent-encoded.
    public var target: String {
        var result = NoteLink.target(for: noteID) + "?text"
        if let section { result += "&section=" + Self.encode(section) }
        if let from { result += "&from=" + Self.encode(from) }
        if let to, to != from { result += "&to=" + Self.encode(to) }
        return result
    }

    public init?(target: String) {
        guard target.lowercased().hasPrefix(NoteLink.prefix) else { return nil }
        let rest = String(target.dropFirst(NoteLink.prefix.count))
        guard let mark = rest.firstIndex(of: "?"), let noteID = UUID(uuidString: String(rest[..<mark])) else { return nil }
        let parts = rest[rest.index(after: mark)...].split(separator: "&").map(String.init)
        guard parts.first == "text" else { return nil }
        var values: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let equals = part.firstIndex(of: "="),
                  let value = String(part[part.index(after: equals)...]).removingPercentEncoding else { return nil }
            values[String(part[..<equals])] = value
        }
        self.init(noteID: noteID, section: values["section"], from: values["from"], to: values["to"])
    }

    /// The beginning of a paragraph's text that names it as an anchor.
    public static func anchor(_ plain: String) -> String {
        let flat = plain.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(anchorLength))
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

/// Either kind of excerpt, as it is written in text and on pages. See ADR 0032 and 0037.
public enum ExcerptTarget: Equatable, Sendable {
    case page(Excerpt)
    case text(TextExcerpt)

    public init?(target: String) {
        if let page = Excerpt(target: target) {
            self = .page(page)
        } else if let text = TextExcerpt(target: target) {
            self = .text(text)
        } else {
            return nil
        }
    }

    public var target: String {
        switch self {
        case let .page(excerpt): excerpt.target
        case let .text(excerpt): excerpt.target
        }
    }

    public var noteID: UUID {
        switch self {
        case let .page(excerpt): excerpt.noteID
        case let .text(excerpt): excerpt.noteID
        }
    }
}
