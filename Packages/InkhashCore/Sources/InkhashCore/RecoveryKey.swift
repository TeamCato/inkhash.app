import CryptoKit
import Foundation

/// Opens the account's vault when no device with an open vault is at hand. Made by the app, never
/// chosen: 24 random Crockford Base32 characters and one check character. See ADR 0054.
public struct RecoveryKey: Equatable, Sendable {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let randomLength = 24
    static let groupLength = 5

    /// The 25 characters without separators, upper case. This is what the vault is wrapped with.
    public let canonical: String

    private init(canonical: String) {
        self.canonical = canonical
    }

    public static func generate() -> RecoveryKey {
        var generator = SystemRandomNumberGenerator()
        let body = String((0..<randomLength).map { _ in alphabet.randomElement(using: &generator)! })
        return RecoveryKey(canonical: body + String(check(body)))
    }

    /// Reads a typed or pasted key. Case, spaces and dashes do not count; `O` reads as `0`, `I` and
    /// `L` as `1`. Nil if it is not a key or the check character does not match.
    public init?(parsing text: String) {
        var body = ""
        for character in text.uppercased() {
            switch character {
            case " ", "-", "\n", "\t": continue
            case "O": body.append("0")
            case "I", "L": body.append("1")
            default:
                guard Self.alphabet.contains(character) else { return nil }
                body.append(character)
            }
        }
        guard body.count == Self.randomLength + 1 else { return nil }
        let random = String(body.prefix(Self.randomLength))
        guard body.last == Self.check(random) else { return nil }
        self.init(canonical: body)
    }

    /// Five groups of five, for reading and writing down.
    public var display: String {
        stride(from: 0, to: canonical.count, by: Self.groupLength).map { start in
            let from = canonical.index(canonical.startIndex, offsetBy: start)
            let to = canonical.index(from, offsetBy: Self.groupLength, limitedBy: canonical.endIndex) ?? canonical.endIndex
            return String(canonical[from..<to])
        }.joined(separator: "-")
    }

    /// The first five bits of SHA-256 over the random part: catches typos before the slow derivation.
    static func check(_ random: String) -> Character {
        let digest = SHA256.hash(data: Data(random.utf8))
        let first = digest.withUnsafeBytes { $0[0] }
        return alphabet[Int(first >> 3)]
    }
}
