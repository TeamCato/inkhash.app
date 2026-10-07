import Foundation

/// Reading and showing server addresses and account ids. See ADR 0018 and 0021.
public enum ServerAddress {
    /// The address if it is http or https with a host, else nil.
    public static func valid(_ text: String) -> URL? {
        guard let parsed = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              parsed.host != nil else { return nil }
        return parsed
    }

    /// The server's admin page, where accounts are created.
    public static func admin(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return "\(base)/admin"
    }

    /// Host and port for showing, `nas:8787`. The address itself if it has no host.
    public static func host(_ url: String) -> String {
        guard let parsed = URL(string: url), let host = parsed.host else { return url }
        return parsed.port.map { "\(host):\($0)" } ?? host
    }

    /// An account id as the device stores it: a lowercased UUID, or nil for anything else.
    public static func accountID(_ raw: String) -> String? {
        UUID(uuidString: raw).map { $0.uuidString.lowercased() }
    }
}
