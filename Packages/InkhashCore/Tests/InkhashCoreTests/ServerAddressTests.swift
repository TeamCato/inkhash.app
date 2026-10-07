import XCTest
@testable import InkhashCore

final class ServerAddressTests: XCTestCase {
    func testValidAddressNeedsHttpAndHost() {
        XCTAssertEqual(ServerAddress.valid(" http://nas:8787 ")?.absoluteString, "http://nas:8787")
        XCTAssertNotNil(ServerAddress.valid("HTTPS://inkhash.example"))
        XCTAssertNil(ServerAddress.valid("ftp://nas"))
        XCTAssertNil(ServerAddress.valid("nas:8787"))
        XCTAssertNil(ServerAddress.valid("http://"))
        XCTAssertNil(ServerAddress.valid(""))
    }

    func testAdminAndHost() {
        XCTAssertEqual(ServerAddress.admin("http://nas:8787/"), "http://nas:8787/admin")
        XCTAssertEqual(ServerAddress.admin(" https://a.example "), "https://a.example/admin")
        XCTAssertEqual(ServerAddress.host("http://192.168.1.10:8787"), "192.168.1.10:8787")
        XCTAssertEqual(ServerAddress.host("https://inkhash.example"), "inkhash.example")
        XCTAssertEqual(ServerAddress.host("kaputt"), "kaputt")
    }

    func testAccountIDIsALowercasedUUID() {
        XCTAssertEqual(
            ServerAddress.accountID("AAAAAAAA-1111-4111-8111-111111111111"),
            "aaaaaaaa-1111-4111-8111-111111111111"
        )
        XCTAssertNil(ServerAddress.accountID("ada"))
    }
}
