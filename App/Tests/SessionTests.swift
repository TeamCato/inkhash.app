import InkhashCore
import XCTest
@testable import Inkhash
import KennelKit

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
        SecretStore.clear(account: VaultSessions.legacyAccount(server))
        UserDefaults.standard.removeObject(forKey: "inkhash.expiredServers")
        try await super.tearDown()
    }

    func testTheTokenFromTheKeychainSignsIn() {
        let sessions = ServerSessions(registry: registry, status: status)
        XCTAssertTrue(sessions.isSignedIn(server))
        XCTAssertEqual(sessions.client(for: server)?.token, "alt")
        XCTAssertEqual(sessions.client(for: server, workspace: "w1")?.workspace, "w1")
    }

    func testABareTokenFromBeforeKennelKitBecomesAWholeSession() throws {
        _ = ServerSessions(registry: registry, status: status)
        let stored = try XCTUnwrap(SecretStore.get(account: SecretStore.key(for: server)))
        let session = try JSONDecoder().decode(KennelSession.self, from: Data(stored.utf8))
        XCTAssertEqual(session.token, "alt")
        XCTAssertEqual(session.address.absoluteString, "http://127.0.0.1:9")
        XCTAssertEqual(session.account.name, "ada")
        XCTAssertTrue(ServerSessions(registry: registry, status: status).isSignedIn(server), "and reads back as JSON")
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

    /// A key an older inkhash kept (ADR 0052) is not used unchecked, and goes when the Kennel goes (ADR 0082).
    func testAKeyFromBeforeIsNotUsedUncheckedAndGoesWithTheKennel() throws {
        let key = VaultKey(keyId: "k", material: Data(repeating: 1, count: 32), epoch: 2)
        try SecretStore.set(String(decoding: try InkhashJSON.encode(key), as: UTF8.self), account: VaultSessions.legacyAccount(server))
        XCTAssertEqual(VaultSessions.legacyKey(for: server), key)
        let vaults = VaultSessions(
            sessions: ServerSessions(registry: registry, status: status), status: status, store: .inMemory())
        XCTAssertNil(vaults.key(for: server), "unchecked against the server, it is not used")
        vaults.forget(server)
        XCTAssertNil(VaultSessions.legacyKey(for: server))
    }

    /// One Kennel per app (ADR 0077): a second server from before goes with its session and key; its workspaces stay.
    func testASecondServerFromBeforeGoesAndItsWorkspacesStay() throws {
        let other = registry.signedIn(url: "http://127.0.0.1:10", accountName: "bea", accountID: UUID().uuidString.lowercased())
        XCTAssertEqual(registry.servers.map(\.id), [other], "signing in to another address replaces the Kennel")
        // A setup from before ADR 0077 with both, the first signed in.
        var setup = registry.setup
        setup.servers.insert(ServerEntry(id: server, url: "http://127.0.0.1:9", accountName: "ada", accountID: "a"), at: 0)
        let linked = Workspace(name: "Arbeit", link: WorkspaceLink(server: other, remote: "w1", sealed: false))
        setup.workspaces.append(linked)
        try Workspaces.save(setup, base: base)
        try SecretStore.set(String(decoding: try InkhashJSON.encode(VaultKey(keyId: "k", material: Data(repeating: 1, count: 32), epoch: 0)), as: UTF8.self), account: VaultSessions.legacyAccount(other))
        defer {
            SecretStore.clear(account: SecretStore.key(for: other))
            SecretStore.clear(account: VaultSessions.legacyAccount(other))
        }
        let reopened = try WorkspaceRegistry(base: base, legacy: nil, status: status)

        let sessions = ServerSessions(registry: reopened, status: status)
        XCTAssertEqual(reopened.servers.map(\.id), [server], "the signed-in one stays")
        XCTAssertTrue(sessions.isSignedIn(server))
        XCTAssertNil(reopened.workspace(linked.id)?.link, "„Nur hier“, with its notes")
        XCTAssertNil(VaultSessions.legacyKey(for: other))
    }
}
