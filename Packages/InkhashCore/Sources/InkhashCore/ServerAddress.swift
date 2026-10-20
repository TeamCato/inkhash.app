import Foundation
import KennelKit

/// Showing server addresses and reading account ids. Reading addresses is `KennelAddress` (ADR 0073).
public enum ServerAddress {
    /// The server's admin page, where accounts are created.
    public static func admin(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return "\(base)/admin"
    }

    /// Host and port for showing, `nas:8790`. The text itself if it is no address.
    public static func host(_ url: String) -> String {
        guard let parsed = URL(string: url), parsed.host != nil else { return url }
        return KennelAddress.display(parsed)
    }

    /// An account id as the device stores it: a lowercased UUID, or nil for anything else.
    public static func accountID(_ raw: String) -> String? {
        UUID(uuidString: raw).map { $0.uuidString.lowercased() }
    }
}
