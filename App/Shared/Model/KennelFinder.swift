import Foundation
import InkhashCore
import Observation
import KennelKit

/// What the connect form shows under „Im Netz gefunden“. A suggestion only: nothing connects
/// before the person picks one and signs in (teamCato ADR 0005).
@MainActor
@Observable
final class KennelFinder {
    private(set) var found: [String] = []
    @ObservationIgnored private let discovery: any KennelDiscovering
    @ObservationIgnored private var browsing: Task<Void, Never>?

    init(discovery: any KennelDiscovering = KennelDiscovery()) {
        self.discovery = discovery
    }

    func start() {
        guard browsing == nil else { return }
        let names = discovery.names()
        browsing = Task { [weak self] in
            for await found in names {
                self?.found = found
            }
        }
    }

    func stop() {
        guard let browsing else { return }
        browsing.cancel()
        self.browsing = nil
        found = []
    }

    func address(of name: String) async -> URL? {
        await discovery.address(of: name)
    }
}
