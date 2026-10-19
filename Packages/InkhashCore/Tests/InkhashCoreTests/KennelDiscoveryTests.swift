import Network
import XCTest
@testable import InkhashCore

final class KennelDiscoveryTests: XCTestCase {
    func testIPv4BecomesAnHttpAddress() {
        XCTAssertEqual(KennelDiscovery.address(host: "192.168.1.10", port: 8790)?.absoluteString, "http://192.168.1.10:8790")
    }

    func testHostNameLosesTheTrailingDot() {
        XCTAssertEqual(KennelDiscovery.address(host: "kennel-ab12.local.", port: 8790)?.absoluteString, "http://kennel-ab12.local:8790")
    }

    func testIPv6GetsBracketsAndAnEscapedZone() {
        XCTAssertEqual(KennelDiscovery.address(host: "fe80::1%en0", port: 8790)?.absoluteString, "http://[fe80::1%25en0]:8790")
        XCTAssertEqual(KennelDiscovery.address(host: "fd00::5", port: 80)?.absoluteString, "http://[fd00::5]:80")
    }

    func testResolvedIPv4LosesItsInterface() throws {
        let scoped = try XCTUnwrap(IPv4Address("192.168.1.5%en0"))
        XCTAssertEqual(KennelDiscovery.address(host: .ipv4(scoped), port: 8790)?.absoluteString, "http://192.168.1.5:8790")
        XCTAssertEqual(KennelDiscovery.address(host: .name("kennel-ab12.local.", nil), port: 8790)?.absoluteString, "http://kennel-ab12.local:8790")
    }

    func testEmptyHostOrPortIsNothing() {
        XCTAssertNil(KennelDiscovery.address(host: "", port: 8790))
        XCTAssertNil(KennelDiscovery.address(host: ".", port: 8790))
        XCTAssertNil(KennelDiscovery.address(host: "nas", port: 0))
    }

    func testJoinLinkFromServerAndCode() {
        XCTAssertEqual(JoinLink.link(server: URL(string: "http://nas:8790/")!, code: "K7Q4-2MPA-XW9D"), "http://nas:8790/join#K7Q4-2MPA-XW9D")
        let link = JoinLink.link(server: URL(string: "https://home.example/kennel")!, code: "K7Q4-2MPA-XW9D")
        XCTAssertEqual(JoinLink.parse(link), JoinTarget(server: URL(string: "https://home.example/kennel")!, code: "K7Q4-2MPA-XW9D"))
    }

    func testCreatingADeviceCodeSendsTheKind() async throws {
        let answer = #"{"id":"0b5c6a7e-1111-4111-8111-111111111111","kind":"device","createdBy":"x","createdAt":"2026-10-19T15:00:00.000Z","expiresAt":"2026-10-19T15:15:00.000Z","code":"K7Q4-2MPA-XW9D"}"#
        let (client, requests) = HTTPStub.client { _ in HTTPStub.json(201, answer) }
        let issued = try await client.createDeviceCode()
        XCTAssertEqual(issued.code, "K7Q4-2MPA-XW9D")
        XCTAssertEqual(issued.expiry, Date(timeIntervalSince1970: 1_792_422_900))
        let sent = try XCTUnwrap(requests().first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/v1/join-codes")
        XCTAssertEqual(sent.headers["Authorization"], "Bearer tok")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: sent.body) as? [String: String], ["kind": "device"])
    }

    func testExpiryWithoutFractionalSeconds() {
        let issued = IssuedJoinCode(id: "a", kind: "device", code: "K7Q4-2MPA-XW9D", expiresAt: "2026-10-19T15:15:00Z")
        XCTAssertEqual(issued.expiry, Date(timeIntervalSince1970: 1_792_422_900))
    }

    func testRevokingDeletesTheCode() async throws {
        let (client, requests) = HTTPStub.client { _ in (204, Data()) }
        try await client.revokeJoinCode(id: "0b5c6a7e-1111-4111-8111-111111111111")
        XCTAssertEqual(requests().first?.method, "DELETE")
        XCTAssertEqual(requests().first?.path, "/v1/join-codes/0b5c6a7e-1111-4111-8111-111111111111")
    }

    func testRevokingAGoneCodeIsNotFound() async {
        let (client, _) = HTTPStub.client { _ in HTTPStub.json(404, #"{"error":"not-found"}"#) }
        do {
            try await client.revokeJoinCode(id: "0b5c6a7e-1111-4111-8111-111111111111")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .notFound)
        }
    }
}
