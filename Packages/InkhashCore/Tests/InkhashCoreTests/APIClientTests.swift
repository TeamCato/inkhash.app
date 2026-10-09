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

    func testVaultIsNilWithoutOne() async throws {
        let (client, requests) = HTTPStub.client { _ in HTTPStub.json(404, #"{"error":"no-vault"}"#) }
        let vault = try await client.vault()
        XCTAssertNil(vault)
        XCTAssertEqual(requests().first?.path, "/v1/vault")
    }

    func testCreatingASecondVaultHandsBackTheFirst() async throws {
        let existing = #"{"error":"vault-exists","vault":{"keyId":"k1","kdf":{"name":"pbkdf2-sha256","rounds":600000,"salt":"AAAA"},"wrapped":"BBBB","epoch":2}}"#
        let (client, requests) = HTTPStub.client { _ in HTTPStub.json(409, existing) }
        let record = VaultRecord(keyId: "k2", kdf: .init(name: "pbkdf2-sha256", rounds: 600_000, salt: "CCCC"), wrapped: "DDDD", epoch: 5)
        do {
            _ = try await client.putVault(record)
            XCTFail("expected an error")
        } catch let APIError.vaultExists(vault) {
            XCTAssertEqual(vault.keyId, "k1")
            XCTAssertEqual(vault.epoch, 2)
        }
        let sent = try JSONSerialization.jsonObject(with: XCTUnwrap(requests().first).body) as? [String: Any]
        XCTAssertNil(sent?["epoch"], "the server counts epochs, not the device")
        XCTAssertEqual(sent?["keyId"] as? String, "k2")
    }

    func testSealedConflictCarriesTheSealedNote() async throws {
        let id = UUID()
        let conflict = #"{"error":"conflict","note":{"schemaVersion":2,"id":"\#(id.uuidString.lowercased())","revision":4,"updatedAt":"t","deletedAt":null,"sealed":"AAAA"}}"#
        let (client, requests) = HTTPStub.client { _ in HTTPStub.json(409, conflict) }
        do {
            _ = try await client.putSealed(SealedUpload(id: id, sealed: "BBBB", deleted: false), baseRevision: 3)
            XCTFail("expected an error")
        } catch let APIError.sealedConflict(note) {
            XCTAssertEqual(note.revision, 4)
        }
        let sent = try JSONSerialization.jsonObject(with: XCTUnwrap(requests().first).body) as? [String: Any]
        XCTAssertEqual(sent?["baseRevision"] as? Int, 3)
        XCTAssertEqual((sent?["note"] as? [String: Any])?["sealed"] as? String, "BBBB")
    }

    func testResetNeedsTheRightPassword() async {
        let (client, _) = HTTPStub.client { _ in HTTPStub.json(403, #"{"error":"wrong-password"}"#) }
        do {
            try await client.resetVault(password: "falsch")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .wrongPassword)
        }
    }
}
