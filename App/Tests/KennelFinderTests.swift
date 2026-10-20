import XCTest
import InkhashCore
@testable import Inkhash
import KennelKit

/// The finder with a discovery that answers like Bonjour would, without the network.
@MainActor
final class KennelFinderTests: XCTestCase {
    private final class FakeDiscovery: KennelDiscovering, @unchecked Sendable {
        // @unchecked: set once in `names()` before the test yields, then only read.
        var continuation: AsyncStream<[String]>.Continuation?
        var stopped = false

        func names() -> AsyncStream<[String]> {
            AsyncStream { continuation in
                self.continuation = continuation
                continuation.onTermination = { _ in self.stopped = true }
            }
        }

        func address(of name: String) async -> URL? {
            name == "Kennel" ? URL(string: "http://192.168.1.10:8790") : nil
        }
    }

    func testFoundNamesShowAndStoppingClearsThem() async throws {
        let discovery = FakeDiscovery()
        let finder = KennelFinder(discovery: discovery)
        finder.start()
        discovery.continuation?.yield(["Keller", "Kennel"])
        for _ in 0..<50 where finder.found.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(finder.found, ["Keller", "Kennel"])
        let address = await finder.address(of: "Kennel")
        XCTAssertEqual(address?.absoluteString, "http://192.168.1.10:8790")
        let gone = await finder.address(of: "Keller")
        XCTAssertNil(gone)
        finder.stop()
        for _ in 0..<50 where !discovery.stopped { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(discovery.stopped)
        XCTAssertEqual(finder.found, [])
    }
}
