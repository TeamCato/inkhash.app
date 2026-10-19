import Foundation
import InkhashCore
import Observation

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
