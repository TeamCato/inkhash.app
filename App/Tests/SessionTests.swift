import InkhashCore
import XCTest
@testable import Inkhash

/// P-027: a session the server no longer knows ends here too, but only the one that was used.
@MainActor
final class SessionTests: LibraryTestCase {
    private var server: UUID!

    override func setUp() async throws {
        try await super.setUp()
        server = registry.signedIn(url: "http://127.0.0.1:9", accountName: "ada", accountID: UUID().uuidString.lowercased())
        try SecretStore.set("alt", account: SecretStore.key(for: server))
    }

    override func tearDown() async throws {
        SecretStore.clear(account: SecretStore.key(for: server))
        SecretStore.clear(account: VaultSessions.keychainAccount(server))
        UserDefaults.standard.removeObject(forKey: "inkhash.expiredServers")
        try await super.tearDown()
    }

    func testTheTokenFromTheKeychainSignsIn() {
        let sessions = ServerSessions(registry: registry, status: status)
        XCTAssertTrue(sessions.isSignedIn(server))
        XCTAssertEqual(sessions.client(for: server)?.token, "alt")
        XCTAssertEqual(sessions.client(for: server, workspace: "w1")?.workspace, "w1")
    }

    func testAnOldRequestDoesNotEndANewSession() {
        let sessions = ServerSessions(registry: registry, status: status)
        sessions.expire(server, ifStill: "noch älter")
        XCTAssertTrue(sessions.isSignedIn(server))
        XCTAssertFalse(sessions.expired.contains(server))
    }

    func testAnExpiredSessionEndsAndSaysSo() {
        let sessions = ServerSessions(registry: registry, status: status)
        sessions.expire(server, ifStill: "alt")
        XCTAssertFalse(sessions.isSignedIn(server))
        XCTAssertTrue(sessions.expired.contains(server))
        XCTAssertNil(SecretStore.get(account: SecretStore.key(for: server)))
        XCTAssertNotNil(registry.server(server), "the server and its workspaces stay")
        XCTAssertEqual(status.message, "Anmeldung abgelaufen. Die Notizen bleiben auf diesem Gerät.")
        // It is remembered across starts until dismissed.
        XCTAssertTrue(ServerSessions(registry: registry, status: status).expired.contains(server))
        sessions.dismissExpiredNotice(server)
        XCTAssertFalse(ServerSessions(registry: registry, status: status).expired.contains(server))
    }

    func testAVaultKeyIsKeptPerServerAndForgottenWithIt() throws {
        let key = VaultKey(keyId: "k", material: Data(repeating: 1, count: 32), epoch: 2)
        try VaultSessions.store(key, for: server)
        XCTAssertEqual(VaultSessions.storedKey(for: server), key)
        let vaults = VaultSessions(sessions: ServerSessions(registry: registry, status: status), status: status)
        XCTAssertNil(vaults.key(for: server), "unchecked against the server, it is not used")
        vaults.forget(server)
        XCTAssertNil(VaultSessions.storedKey(for: server))
    }

    func testPostponingAVaultPromptKeepsItAwayUntilAsked() {
        let vaults = VaultSessions(sessions: ServerSessions(registry: registry, status: status), status: status)
        vaults.prompt = server
        vaults.postpone(server)
        XCTAssertNil(vaults.prompt)
    }
}
