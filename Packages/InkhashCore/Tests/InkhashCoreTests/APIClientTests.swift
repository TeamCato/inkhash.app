import KennelKit
import XCTest
@testable import InkhashCore

final class APIClientTests: XCTestCase {
    func testWorkspaceRoutesCarryThePrefix() async throws {
        let page = #"{"cursor":0,"changes":[],"hasMore":false}"#
        let (main, mainRequests) = HTTPStub.client { _ in HTTPStub.json(200, page) }
        _ = try await main.changes(after: 3)
        XCTAssertEqual(mainRequests().first?.path, "/v1/apps/inkhash/changes")
        XCTAssertEqual(mainRequests().first?.query, "after=3")
        let (other, otherRequests) = HTTPStub.client(workspace: "abc") { _ in HTTPStub.json(200, page) }
        _ = try await other.changes(after: 0)
        XCTAssertEqual(otherRequests().first?.path, "/v1/apps/inkhash/workspaces/abc/changes")
    }

    func testHealthReadsTheModuleOfKennel() async throws {
        let kennel = #"{"ok":true,"server":"kennel","version":"0.1.0","registration":"closed","modules":{"inkhash":{"title":"inkhash","encryption":"required","vault":true,"workspaces":true,"pairing":true}}}"#
        let (client, requests) = HTTPStub.client { _ in HTTPStub.json(200, kennel) }
        let health = try await client.kennel.health()
        XCTAssertEqual(requests().first?.path, "/v1/health")
        XCTAssertTrue(health.isKennel)
        XCTAssertEqual(health.inkhash?.pairing, true)
        XCTAssertTrue(health.inkhashVault)
    }

    func testHealthWithoutTheModuleHasNoVault() async throws {
        // The old inkhashd, or a Kennel with inkhash switched off.
        let old = #"{"ok":true,"registration":"closed","version":"0.6.0","vault":true}"#
        let (client, _) = HTTPStub.client { _ in HTTPStub.json(200, old) }
        let health = try await client.kennel.health()
        XCTAssertNil(health.inkhash)
        XCTAssertFalse(health.inkhashVault)
    }

    func testVaultIsNilWithoutOne() async throws {
        let (client, requests) = HTTPStub.client { _ in HTTPStub.json(404, #"{"error":"no-vault"}"#) }
        let vault = try await client.vault()
        XCTAssertNil(vault)
        XCTAssertEqual(requests().first?.path, "/v1/apps/inkhash/vault")
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

    func testNewWorkspaceSendsItsLayoutOnlyWhenChosen() async throws {
        let reply = #"{"id":"w1","name":"Haushalt","sealed":false,"storageId":"s1"}"#
        let (client, requests) = HTTPStub.client { _ in HTTPStub.json(201, reply) }
        let created = try await client.createWorkspace(name: "Haushalt", as: NewRemoteWorkspace(sealed: false, storageID: "s1"))
        _ = try await client.createWorkspace(name: "Privat")
        let bodies = try requests().map { try JSONSerialization.jsonObject(with: $0.body) as? [String: AnyHashable] }
        XCTAssertEqual(bodies[0], ["name": "Haushalt", "sealed": false, "storageId": "s1"])
        XCTAssertEqual(bodies[1], ["name": "Privat"])
        XCTAssertFalse(created.isSealed)
        XCTAssertEqual(created.storageId, "s1")
        XCTAssertTrue(RemoteWorkspace(id: "main", name: "Privat").isSealed, "older servers seal everything")
    }

    func testLinksFromBeforeAreSealed() throws {
        let old = #"{"server":"6F1C3A2E-7B64-4D1A-9C3E-2A8B0D5E7F10","remote":"main"}"#
        let link = try JSONDecoder().decode(WorkspaceLink.self, from: Data(old.utf8))
        XCTAssertTrue(link.sealed)
        let plain = WorkspaceLink(server: link.server, remote: "w1", sealed: false)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceLink.self, from: JSONEncoder().encode(plain)), plain)
    }


    func testMovingAWorkspaceSendsTheStorageOrNull() async throws {
        let reply = #"{"id":"w1","name":"Haushalt","storageId":"s1","move":{"to":"s2","state":"running","detail":null}}"#
        let (client, requests) = HTTPStub.client { _ in HTTPStub.json(202, reply) }
        let moved = try await client.moveWorkspace(id: "w1", to: "s2")
        _ = try await client.moveWorkspace(id: "w1", to: nil)
        XCTAssertEqual(requests().first?.path, "/v1/apps/inkhash/workspaces/w1/storage")
        XCTAssertEqual(requests().first?.method, "PUT")
        let bodies = try requests().map { try JSONSerialization.jsonObject(with: $0.body) as? [String: Any] }
        XCTAssertEqual(bodies[0]?["storageId"] as? String, "s2")
        XCTAssertTrue(bodies[1]?["storageId"] is NSNull)
        XCTAssertEqual(moved.move, RemoteMove(to: "s2", state: "running"))
        XCTAssertTrue(moved.move?.isRunning == true)
    }

}
