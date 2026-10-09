import XCTest
@testable import InkhashCore

final class APIClientTests: XCTestCase {
    func testChangePasswordSendsBothPasswords() async throws {
        let (client, requests) = HTTPStub.client { _ in (204, Data()) }
        try await client.changePassword(current: "altesalt", to: "neuesneu")
        let sent = try XCTUnwrap(requests().first)
        XCTAssertEqual(sent.method, "PUT")
        XCTAssertEqual(sent.path, "/v1/password")
        XCTAssertEqual(sent.headers["Authorization"], "Bearer tok")
        let body = try JSONSerialization.jsonObject(with: sent.body) as? [String: String]
        XCTAssertEqual(body, ["current": "altesalt", "password": "neuesneu"])
    }

    func testWrongCurrentPasswordIsItsOwnError() async {
        let (client, _) = HTTPStub.client { _ in HTTPStub.json(403, #"{"error":"wrong-password"}"#) }
        do {
            try await client.changePassword(current: "falsch", to: "neuesneu")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .wrongPassword)
        }
    }

    func testOtherRefusalsStayStatusErrors() async {
        let (client, _) = HTTPStub.client { _ in HTTPStub.json(400, #"{"error":"bad-request"}"#) }
        do {
            try await client.changePassword(current: "altesalt", to: "kurz")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .badStatus(400, #"{"error":"bad-request"}"#))
        }
    }

    func testWorkspaceRoutesCarryThePrefix() async throws {
        let page = #"{"cursor":0,"changes":[],"hasMore":false}"#
        let (main, mainRequests) = HTTPStub.client { _ in HTTPStub.json(200, page) }
        _ = try await main.changes(after: 3)
        XCTAssertEqual(mainRequests().first?.path, "/v1/changes")
        XCTAssertEqual(mainRequests().first?.query, "after=3")
        let (other, otherRequests) = HTTPStub.client(workspace: "abc") { _ in HTTPStub.json(200, page) }
        _ = try await other.changes(after: 0)
        XCTAssertEqual(otherRequests().first?.path, "/v1/workspaces/abc/changes")
    }
}
