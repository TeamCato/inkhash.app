import Foundation
import InkhashCore
import Network
import Observation

/// Looks for Kennel in the home network. Behind a protocol so the connect form can be shown
/// without the network. See ADR 0072.
protocol KennelBrowsing: AnyObject, Sendable {
    /// Starts looking; `update` hears the instance names found so far, on any queue, after each change.
    func start(update: @escaping @Sendable ([String]) -> Void)
    func stop()
    /// The address of a found instance, nil if it cannot be reached or is gone.
    func address(of name: String) async -> URL?
}

/// What the connect form shows under „Im Netz gefunden“. A suggestion only: nothing connects
/// before the person picks one and signs in (teamCato ADR 0005).
@MainActor
@Observable
final class KennelFinder {
    private(set) var found: [String] = []
    @ObservationIgnored private let browser: any KennelBrowsing
    @ObservationIgnored private var running = false

    init(browser: any KennelBrowsing = BonjourKennelBrowser()) {
        self.browser = browser
    }

    func start() {
        guard !running else { return }
        running = true
        browser.start { [weak self] names in
            Task { @MainActor in self?.found = names }
        }
    }

    func stop() {
        guard running else { return }
        running = false
        browser.stop()
        found = []
    }

    func address(of name: String) async -> URL? {
        await browser.address(of: name)
    }
}

/// Browses `_kennel._tcp` with the Network framework and resolves an instance by connecting to it.
final class BonjourKennelBrowser: KennelBrowsing, @unchecked Sendable {
    // @unchecked: `browser` and `endpoints` are only touched on `queue`.
    private let queue = DispatchQueue(label: "inkhash.kennel-browser")
    private var browser: NWBrowser?
    private var endpoints: [String: NWEndpoint] = [:]
    private static let resolveTimeout: TimeInterval = 5

    func start(update: @escaping @Sendable ([String]) -> Void) {
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

    func stop() {
        queue.async {
            self.browser?.cancel()
            self.browser = nil
            self.endpoints = [:]
        }
    }

    func address(of name: String) async -> URL? {
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
                        url = KennelDiscovery.address(host: Self.text(of: host), port: port.rawValue)
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

    private static func text(of host: NWEndpoint.Host) -> String {
        switch host {
        case .name(let name, _): name
        case .ipv4(let address): "\(address)"
        case .ipv6(let address): "\(address)"
        @unknown default: "\(host)"
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
