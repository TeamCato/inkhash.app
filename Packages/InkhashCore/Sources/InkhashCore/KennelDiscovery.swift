import Foundation
import Network

/// Finding Kennel in the home network with Bonjour: what a found service turns into, and the
/// browser itself. See ADR 0072, Kennel ADR 0019.
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

    /// The address of a resolved endpoint. An IPv4 address is built from its bytes: its text
    /// carries the interface after a resolve (`192.168.1.5%en0`), which no URL takes.
    public static func address(host: NWEndpoint.Host, port: UInt16) -> URL? {
        switch host {
        case .ipv4(let ip): address(host: ip.rawValue.map(String.init).joined(separator: "."), port: port)
        case .ipv6(let ip): address(host: "\(ip)", port: port)
        case .name(let name, _): address(host: name, port: port)
        @unknown default: nil
        }
    }
}

/// Looks for Kennel in the home network. Behind a protocol so the connect form can be shown
/// without the network. See ADR 0072.
public protocol KennelBrowsing: AnyObject, Sendable {
    /// Starts looking; `update` hears the instance names found so far, on any queue, after each change.
    func start(update: @escaping @Sendable ([String]) -> Void)
    func stop()
    /// The address of a found instance, nil if it cannot be reached or is gone.
    func address(of name: String) async -> URL?
}

/// Browses `_kennel._tcp` with the Network framework and resolves an instance by connecting to it.
public final class BonjourKennelBrowser: KennelBrowsing, @unchecked Sendable {
    public init() {}

    // @unchecked: `browser` and `endpoints` are only touched on `queue`.
    private let queue = DispatchQueue(label: "inkhash.kennel-browser")
    private var browser: NWBrowser?
    private var endpoints: [String: NWEndpoint] = [:]
    private static let resolveTimeout: TimeInterval = 5

    public func start(update: @escaping @Sendable ([String]) -> Void) {
        queue.async {
            guard self.browser == nil else { return }
            let browser = NWBrowser(for: .bonjour(type: KennelDiscovery.serviceType, domain: nil), using: NWParameters())
            browser.browseResultsChangedHandler = { results, _ in
                var endpoints: [String: NWEndpoint] = [:]
                for result in results {
                    if case let .service(name, _, _, _) = result.endpoint { endpoints[name] = result.endpoint }
                }
                self.endpoints = endpoints
                update(endpoints.keys.sorted())
            }
            browser.start(queue: self.queue)
            self.browser = browser
        }
    }

    public func stop() {
        queue.async {
            self.browser?.cancel()
            self.browser = nil
            self.endpoints = [:]
        }
    }

    public func address(of name: String) async -> URL? {
        let endpoint = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.endpoints[name]) }
        }
        guard let endpoint else { return nil }
        // Kennel announces only IPv4 (Kennel ADR 0019).
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let answer = ResolveAnswer()
        return await withCheckedContinuation { continuation in
            answer.continuation = continuation
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var url: URL?
                    if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                        url = KennelDiscovery.address(host: host, port: port.rawValue)
                    }
                    answer.give(url)
                    connection.cancel()
                case .waiting, .failed:
                    answer.give(nil)
                    connection.cancel()
                case .cancelled:
                    answer.give(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + Self.resolveTimeout) {
                answer.give(nil)
                connection.cancel()
            }
        }
    }
}
/// Resumes its continuation once, whichever of connection and timeout answers first.
private final class ResolveAnswer: @unchecked Sendable {
    // @unchecked: only touched on the browser's queue, and once when it is set before starting.
    var continuation: CheckedContinuation<URL?, Never>?

    func give(_ url: URL?) {
        continuation?.resume(returning: url)
        continuation = nil
    }
}

