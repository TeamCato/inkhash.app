import Foundation

/// What the paper of a note shows under the writing. See ADR 0042.
public enum PaperPattern: String, Codable, CaseIterable, Sendable {
    case blank, grid, lines, dots

    /// Distance between lines or dots, in page points.
    public var spacing: Double {
        switch self {
        case .blank: 0
        case .grid, .dots: 32
        case .lines: 36
        }
    }

    /// Where the first line or dot sits, in page points from the top.
    public var start: Double {
        switch self {
        case .lines: 72
        default: spacing
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

/// The paper of a note: one colour and, for handwriting, one pattern for every page. See ADR 0042.
public struct Paper: Equatable, Codable, Sendable {
    /// `#RRGGBB`, upper case.
    public var color: String
    public var pattern: PaperPattern

    public init(color: String, pattern: PaperPattern = .blank) {
        self.color = color.uppercased()
        self.pattern = pattern
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
        case color, pattern
    }

    /// A pattern from a newer app is read as blank, so the note still opens.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        color = try container.decode(String.self, forKey: .color).uppercased()
        let raw = try container.decodeIfPresent(String.self, forKey: .pattern) ?? PaperPattern.blank.rawValue
        pattern = PaperPattern(rawValue: raw) ?? .blank
    }
}
