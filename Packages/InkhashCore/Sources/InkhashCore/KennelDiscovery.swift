import Foundation

/// Finding Kennel in the home network with Bonjour. The browsing itself lives in the app; this is
/// what a found service turns into. See ADR 0072, Kennel ADR 0019.
public enum KennelDiscovery {
    /// The DNS-SD service type Kennel announces.
    public static let serviceType = "_kennel._tcp"

    /// The address of a resolved service: `http://<host>:<port>`. The host may be a name with or
    /// without the trailing dot of DNS, an IPv4 or an IPv6 address with a zone (`fe80::1%en0`).
    /// Nil for an empty host or port 0.
    public static func address(host raw: String, port: UInt16) -> URL? {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, port > 0 else { return nil }
        if host.contains(":") {
            host = "[" + host.replacingOccurrences(of: "%", with: "%25") + "]"
        }
        return ServerAddress.valid("http://\(host):\(port)")
    }
}
