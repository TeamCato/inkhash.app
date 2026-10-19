import XCTest
@testable import InkhashCore

final class KennelJoinTests: XCTestCase {
    func testCodeIsReadGenerously() {
        XCTAssertEqual(JoinCode.normalized("K7Q4-2MPA-XW9D"), "K7Q4-2MPA-XW9D")
        XCTAssertEqual(JoinCode.normalized(" k7q4 2mpa xw9d "), "K7Q4-2MPA-XW9D")
        XCTAssertEqual(JoinCode.normalized("k7q42mpaxw9d"), "K7Q4-2MPA-XW9D")
        XCTAssertEqual(JoinCode.normalized("OIL0-0000-0000"), "0110-0000-0000")
    }

    func testCodeRefusesWrongLengthAndLetters() {
        XCTAssertNil(JoinCode.normalized("K7Q4-2MPA-XW9"))
        XCTAssertNil(JoinCode.normalized("K7Q4-2MPA-XW9DD"))
        XCTAssertNil(JoinCode.normalized("K7Q4-2MPA-XW9U"))
        XCTAssertNil(JoinCode.normalized("K7Q4-2MPA-XW9!"))
        XCTAssertNil(JoinCode.normalized(""))
    }

    func testJoinLinkCarriesServerAndCode() {
        let target = JoinLink.parse("http://kennel.local:8790/join#k7q4-2mpa-xw9d")
        XCTAssertEqual(target?.server.absoluteString, "http://kennel.local:8790")
        XCTAssertEqual(target?.code, "K7Q4-2MPA-XW9D")
    }

    func testJoinLinkUnderAPathKeepsThePath() {
        let target = JoinLink.parse("https://home.example/kennel/join/#K7Q4-2MPA-XW9D")
        XCTAssertEqual(target?.server.absoluteString, "https://home.example/kennel")
        XCTAssertEqual(target?.code, "K7Q4-2MPA-XW9D")
    }

    func testAppLinkCarriesServerAndCode() {
        let target = JoinLink.parse("inkhash://kennel/join?server=http%3A%2F%2F192.168.1.10%3A8790&code=K7Q4-2MPA-XW9D")
        XCTAssertEqual(target?.server.absoluteString, "http://192.168.1.10:8790")
        XCTAssertEqual(target?.code, "K7Q4-2MPA-XW9D")
    }

    func testAppLinkWithoutCodeIsTheAddress() {
        let target = JoinLink.parse("inkhash://kennel/join?server=http%3A%2F%2Fnas%3A8790")
        XCTAssertEqual(target, JoinTarget(server: URL(string: "http://nas:8790")!, code: nil))
    }

    func testOtherAppLinksAreNotOurs() {
        XCTAssertNil(JoinLink.parse("inkhash://kennel/other?server=http%3A%2F%2Fnas"))
        XCTAssertNil(JoinLink.parse("inkhash://kennel/join?server=ftp%3A%2F%2Fnas"))
        XCTAssertNil(JoinLink.parse("xoot://kennel/join?server=http%3A%2F%2Fnas&code=K7Q4-2MPA-XW9D"))
    }

    func testPlainAddressHasNoCode() {
        XCTAssertEqual(JoinLink.parse(" http://nas:8790 "), JoinTarget(server: URL(string: "http://nas:8790")!, code: nil))
        XCTAssertEqual(JoinLink.parse("http://nas:8790/"), JoinTarget(server: URL(string: "http://nas:8790/")!, code: nil))
        XCTAssertEqual(JoinLink.parse("http://nas:8790/join")?.server.absoluteString, "http://nas:8790")
        XCTAssertNil(JoinLink.parse("nas:8790"))
        XCTAssertNil(JoinLink.parse(""))
    }

    func testOnlyLinksWithACodeCountAsScannedJoinLinks() {
        XCTAssertTrue(JoinLink.isJoinLink("http://nas:8790/join#K7Q4-2MPA-XW9D"))
        XCTAssertFalse(JoinLink.isJoinLink("http://nas:8790"))
        XCTAssertFalse(JoinLink.isJoinLink("inkhash-pair:abc"))
    }

    func testDeviceCodeSendsOnlyTheCode() async throws {
        let (client, requests) = HTTPStub.client { _ in
            HTTPStub.json(200, #"{"token":"t1","account":{"id":"aaaaaaaa-1111-4111-8111-111111111111","name":"ada","admin":false}}"#)
        }
        let session = try await client.join(code: "K7Q4-2MPA-XW9D")
        XCTAssertEqual(session.token, "t1")
        XCTAssertEqual(session.account.name, "ada")
        let sent = try XCTUnwrap(requests().first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/v1/join")
        XCTAssertNil(sent.headers["Authorization"])
        XCTAssertEqual(try JSONSerialization.jsonObject(with: sent.body) as? [String: String], ["code": "K7Q4-2MPA-XW9D"])
    }

    func testInviteWithoutAccountAsksForOne() async {
        let (client, _) = HTTPStub.client { _ in HTTPStub.json(400, #"{"error":"bad-request","reason":"name"}"#) }
        do {
            _ = try await client.join(code: "K7Q4-2MPA-XW9D")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? JoinError, .needsAccount)
        }
    }

    func testInviteSendsNameAndPassword() async throws {
        let (client, requests) = HTTPStub.client { _ in
            HTTPStub.json(201, #"{"token":"t2","account":{"id":"aaaaaaaa-1111-4111-8111-111111111111","name":"bea","admin":false}}"#)
        }
        let session = try await client.join(code: "K7Q4-2MPA-XW9D", name: "bea", password: "secretsecret")
        XCTAssertEqual(session.token, "t2")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(requests().first).body) as? [String: String]
        XCTAssertEqual(body, ["code": "K7Q4-2MPA-XW9D", "name": "bea", "password": "secretsecret"])
    }

    func testTakenNameIsItsOwnError() async {
        let (client, _) = HTTPStub.client { _ in HTTPStub.json(409, #"{"error":"name-taken"}"#) }
        do {
            _ = try await client.join(code: "K7Q4-2MPA-XW9D", name: "ada", password: "secretsecret")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? JoinError, .nameTaken)
        }
    }

    func testUnusableCodeIsUnauthorized() async {
        let (client, _) = HTTPStub.client { _ in HTTPStub.json(401, #"{"error":"unauthorized"}"#) }
        do {
            _ = try await client.join(code: "K7Q4-2MPA-XW9D")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }
}
