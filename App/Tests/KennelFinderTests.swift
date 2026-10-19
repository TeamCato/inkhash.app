import XCTest
@testable import Inkhash

/// The finder with a browser that answers like Bonjour would, without the network.
@MainActor
final class KennelFinderTests: XCTestCase {
    private final class FakeBrowser: KennelBrowsing, @unchecked Sendable {
        var update: (@Sendable ([String]) -> Void)?
        var stopped = false

        func start(update: @escaping @Sendable ([String]) -> Void) { self.update = update }
        func stop() { stopped = true }
        func address(of name: String) async -> URL? {
            name == "Kennel" ? URL(string: "http://192.168.1.10:8790") : nil
        }
    }

    func testFoundNamesShowAndStoppingClearsThem() async throws {
        let browser = FakeBrowser()
        let finder = KennelFinder(browser: browser)
        finder.start()
        browser.update?(["Kennel", "Keller"])
        for _ in 0..<50 where finder.found.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(finder.found, ["Kennel", "Keller"])
        let address = await finder.address(of: "Kennel")
        XCTAssertEqual(address?.absoluteString, "http://192.168.1.10:8790")
        let gone = await finder.address(of: "Keller")
        XCTAssertNil(gone)
        finder.stop()
        XCTAssertTrue(browser.stopped)
        XCTAssertEqual(finder.found, [])
    }
}
