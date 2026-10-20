import XCTest
@testable import InkhashCore

final class ServerAddressTests: XCTestCase {
    func testAdminAndHost() {
        XCTAssertEqual(ServerAddress.admin("http://nas:8787/"), "http://nas:8787/admin")
        XCTAssertEqual(ServerAddress.admin(" https://a.example "), "https://a.example/admin")
        XCTAssertEqual(ServerAddress.host("http://192.168.1.10:8787"), "192.168.1.10:8787")
        XCTAssertEqual(ServerAddress.host("https://inkhash.example"), "inkhash.example")
        XCTAssertEqual(ServerAddress.host("kaputt"), "kaputt")
        XCTAssertEqual(ServerAddress.host("https://home.example/kennel"), "home.example/kennel")
    }

    func testAccountIDIsALowercasedUUID() {
        XCTAssertEqual(
            ServerAddress.accountID("AAAAAAAA-1111-4111-8111-111111111111"),
            "aaaaaaaa-1111-4111-8111-111111111111"
        )
        XCTAssertNil(ServerAddress.accountID("ada"))
    }
}
