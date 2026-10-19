import Foundation

/// A join code of Kennel: twelve Crockford Base32 characters, shown as `XXXX-XXXX-XXXX`.
/// Read generously like Kennel does. See ADR 0071, teamCato ADR 0004.
public enum JoinCode {
    public static let alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    public static let length = 12

    /// The code as Kennel shows it, or nil if the text is no code. Case does not matter, dashes and
    /// spaces fall away, `O` reads as `0`, `I` and `L` as `1`.
    public static func normalized(_ raw: String) -> String? {
        var plain = ""
        for character in raw.uppercased() {
            switch character {
            case "-", " ", "\t", "\n", "\r": continue
            case "O": plain.append("0")
            case "I", "L": plain.append("1")
            default:
                guard alphabet.contains(character) else { return nil }
                plain.append(character)
            }
        }
        guard plain.count == length else { return nil }
        let chars = Array(plain)
        return [chars[0..<4], chars[4..<8], chars[8..<12]].map { String($0) }.joined(separator: "-")
    }
}

/// Where a pasted or opened text points: the server's address, and a code if it carried one.
public struct JoinTarget: Hashable, Sendable {
    public var server: URL
    /// Normalized, `XXXX-XXXX-XXXX`. Nil for a plain address, or a link whose code is unreadable.
    public var code: String?

    public init(server: URL, code: String?) {
        self.server = server
        self.code = code
    }
}

/// Reads join link, app link or plain address. See ADR 0071, teamCato ADR 0004.
public enum JoinLink {
    /// The URL scheme the app registers; Kennel's module reports it in `/v1/health`.
    public static let appScheme = "inkhash"

    /// - `<server>/join#<code>`, the join link Kennel's admin page shows as text and QR code
    /// - `inkhash://kennel/join?server=<server>&code=<code>`, the app link from Kennel's page `/join`
    /// - a plain `http` or `https` address
    /// Nil for anything else.
    public static func parse(_ text: String) -> JoinTarget? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased() else { return nil }
        if scheme == appScheme {
            return appLink(components)
        }
        guard ["http", "https"].contains(scheme), components.host?.isEmpty == false else { return nil }
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        guard path.hasSuffix("/join") else {
            // A plain address stays as typed, so a known server is found by it again.
            return ServerAddress.valid(trimmed).map { JoinTarget(server: $0, code: nil) }
        }
        var base = components
        base.fragment = nil
        base.query = nil
        base.path = String(path.dropLast("/join".count))
        guard let server = base.url.flatMap({ ServerAddress.valid($0.absoluteString) }) else { return nil }
        return JoinTarget(server: server, code: components.fragment.flatMap(JoinCode.normalized))
    }

    /// Whether a scanned QR code is a join link with a code. Plain addresses do not count.
    public static func isJoinLink(_ text: String) -> Bool {
        parse(text)?.code != nil
    }

    private static func appLink(_ components: URLComponents) -> JoinTarget? {
        guard components.host?.lowercased() == "kennel", components.path == "/join" else { return nil }
        let items = components.queryItems ?? []
        guard let raw = items.first(where: { $0.name == "server" })?.value,
              let server = ServerAddress.valid(raw) else { return nil }
        let code = items.first(where: { $0.name == "code" })?.value.flatMap(JoinCode.normalized)
        return JoinTarget(server: server, code: code)
    }
}

/// Why redeeming a join code needs another try. Every unusable code is `APIError.unauthorized`.
public enum JoinError: Error, Equatable {
    /// The code is an invite: it needs a name and a password for the new account. It stays valid.
    case needsAccount
    /// An invite with a name another account already has. It stays valid.
    case nameTaken
}
