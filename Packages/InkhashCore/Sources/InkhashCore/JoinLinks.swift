import Foundation
import KennelKit

/// Join links as inkhash reads them: KennelKit's rules with the app's URL scheme (ADR 0071, 0073).
public enum JoinLinks {
    /// The URL scheme the app registers; Kennel's module reports it in `/v1/health`.
    public static let scheme = "inkhash"

    public static func parse(_ text: String) -> JoinLink? {
        JoinLink.parse(text, appScheme: scheme)
    }

    /// Whether a scanned QR code is a join link with a code. Plain addresses do not count.
    public static func isJoinLink(_ text: String) -> Bool {
        JoinLink.isJoinLink(text, appScheme: scheme)
    }
}
