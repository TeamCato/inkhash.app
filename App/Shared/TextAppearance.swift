import Foundation

/// The family text notes are set in on this device. See ADR 0061.
enum TextFamily: String, CaseIterable, Identifiable {
    case standard, serif, rounded, mono

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .serif: "Serif"
        case .rounded: "Abgerundet"
        case .mono: "Monospace"
        }
    }
}

/// Font and size of text notes, chosen per device and not synced. Without a choice it is what
/// ADR 0053 sets. See ADR 0061.
struct TextAppearance: Equatable {
    static let familyKey = "text.family"
    static let sizeKey = "text.size"
    static let defaultSize: Double = 17
    static let sizes: ClosedRange<Double> = 13...24

    var family: TextFamily
    var size: Double

    static var current: TextAppearance {
        let defaults = UserDefaults.standard
        let family = defaults.string(forKey: familyKey).flatMap(TextFamily.init(rawValue:)) ?? .standard
        let stored = defaults.double(forKey: sizeKey)
        let size = stored == 0 ? defaultSize : min(max(stored, sizes.lowerBound), sizes.upperBound)
        return TextAppearance(family: family, size: size)
    }

    /// How much larger than the default everything in a text note is.
    var scale: CGFloat { CGFloat(size / Self.defaultSize) }
}
