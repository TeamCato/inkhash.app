import Foundation

/// What the paper of a note shows under the writing. See ADR 0042.
public enum PaperPattern: String, Codable, CaseIterable, Sendable {
    case blank, grid, lines, dots

    /// Distance between lines or dots without a chosen spacing, in page points.
    public var defaultSpacing: Int {
        switch self {
        case .blank: 0
        case .grid, .dots: 32
        case .lines: 36
        }
    }

    /// Where the first line or dot sits without a chosen start, in page points from the top.
    public func defaultStart(spacing: Int) -> Int {
        switch self {
        case .blank: 0
        case .lines: 72
        case .grid, .dots: spacing
        }
    }

    public var label: String {
        switch self {
        case .blank: "Leer"
        case .grid: "Kariert"
        case .lines: "Liniert"
        case .dots: "Gepunktet"
        }
    }
}

/// The paper of a note: one colour and, for handwriting, one pattern for every page. See ADR 0042
/// and, for spacing and start, ADR 0047 and 0055.
public struct Paper: Equatable, Codable, Sendable {
    /// `#RRGGBB`, upper case.
    public var color: String
    /// Set through `init`, so the spacing always fits the pattern.
    public private(set) var pattern: PaperPattern
    /// Distance between lines or dots in page points, or nil for the pattern's default. Never set
    /// for a blank pattern or to the default itself, so an unchanged note stays the same.
    public private(set) var spacing: Int?
    /// Where the first row of the pattern lies in page points from the top, or nil for the
    /// pattern's default. Same rules as `spacing`.
    public private(set) var start: Int?

    /// The spacings a pattern may have, in page points.
    public static let spacingRange = 20...64
    public static let spacingStep = 2
    /// The starts a pattern may have, in page points.
    public static let startRange = 0...200

    /// A spacing or start outside its range is clamped to it.
    public init(color: String, pattern: PaperPattern = .blank, spacing: Int? = nil, start: Int? = nil) {
        self.color = color.uppercased()
        self.pattern = pattern
        let spacing = Paper.normalized(spacing, in: Paper.spacingRange, pattern: pattern, default: pattern.defaultSpacing)
        self.spacing = spacing
        let shownSpacing = spacing ?? pattern.defaultSpacing
        self.start = Paper.normalized(start, in: Paper.startRange, pattern: pattern, default: pattern.defaultStart(spacing: shownSpacing))
    }

    /// The distance the pattern is drawn with: the chosen spacing or the pattern's default.
    public var shownSpacing: Int { spacing ?? pattern.defaultSpacing }

    /// Where the first row is drawn: the chosen start or the pattern's default.
    public var shownStart: Int { start ?? pattern.defaultStart(spacing: shownSpacing) }

    /// The same paper with another pattern; spacing and start come along. See ADR 0047 and 0055.
    public func with(pattern: PaperPattern) -> Paper {
        Paper(color: color, pattern: pattern, spacing: spacing, start: start)
    }

    /// The same paper in another colour.
    public func with(color: String) -> Paper {
        Paper(color: color, pattern: pattern, spacing: spacing, start: start)
    }

    private static func normalized(_ value: Int?, in range: ClosedRange<Int>, pattern: PaperPattern, default standard: Int) -> Int? {
        guard let value, pattern != .blank else { return nil }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return clamped == standard ? nil : clamped
    }

    /// The paper of a note without `paper`.
    public static let standard = Paper(color: "#FDFDFC")

    /// Light tones only, so ink stays readable. The first is the standard.
    public static let palette: [(name: String, color: String)] = [
        ("Weiß", "#FDFDFC"),
        ("Creme", "#FAF5E8"),
        ("Grau", "#F1F2F4"),
        ("Gelb", "#FBF4D5"),
        ("Grün", "#ECF4EA"),
        ("Blau", "#EAF1FA"),
    ]

    /// Red, green and blue from 0 to 1, or nil for a malformed colour.
    public var components: (red: Double, green: Double, blue: Double)? {
        let hex = color.dropFirst()
        guard color.hasPrefix("#"), hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    enum CodingKeys: String, CodingKey {
        case color, pattern, spacing, start
    }

    /// A pattern from a newer app is read as blank and a spacing or start that is not a whole
    /// number in range as the default, so the note still opens.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let color = try container.decode(String.self, forKey: .color)
        let raw = try container.decodeIfPresent(String.self, forKey: .pattern) ?? PaperPattern.blank.rawValue
        let spacing = (try? container.decodeIfPresent(Int.self, forKey: .spacing)) ?? nil
        let start = (try? container.decodeIfPresent(Int.self, forKey: .start)) ?? nil
        self.init(
            color: color,
            pattern: PaperPattern(rawValue: raw) ?? .blank,
            spacing: spacing.flatMap { Paper.spacingRange.contains($0) ? $0 : nil },
            start: start.flatMap { Paper.startRange.contains($0) ? $0 : nil }
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(color, forKey: .color)
        try container.encode(pattern, forKey: .pattern)
        try container.encodeIfPresent(spacing, forKey: .spacing)
        try container.encodeIfPresent(start, forKey: .start)
    }
}
