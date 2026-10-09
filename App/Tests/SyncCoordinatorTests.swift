import InkhashCore
import XCTest
@testable import Inkhash

/// Syncing waits for the vault: without an open key nothing leaves the device. See ADR 0052.
@MainActor
final class SyncCoordinatorTests: LibraryTestCase {
    private var server: UUID!

    override func setUp() async throws {
        try await super.setUp()
        // Nothing listens on port 9: every request fails at once.
        server = registry.signedIn(url: "http://127.0.0.1:9", accountName: "ada", accountID: UUID().uuidString.lowercased())
        try SecretStore.set("tok", account: SecretStore.key(for: server))
        XCTAssertTrue(registry.setLink(registry.current.id, to: WorkspaceLink(server: server, remote: APIClient.mainWorkspace)))
    }

    override func tearDown() async throws {
        SecretStore.clear(account: SecretStore.key(for: server))
        SecretStore.clear(account: VaultSessions.keychainAccount(server))
        try await super.tearDown()
    }

    func testWithoutAnOpenVaultNothingIsSent() async throws {
        var note = Note.newText(now: "2026-10-01T08:00:00Z")
        note.applyMarkdown("# Lokal\n")
        library.add(note)
        let sessions = ServerSessions(registry: registry, status: status)
        let vaults = VaultSessions(sessions: sessions, status: status)
        let coordinator = SyncCoordinator(registry: registry, sessions: sessions, vaults: vaults, library: library, status: status)
        XCTAssertTrue(coordinator.isEnabled)
        await coordinator.sync()
        XCTAssertNil(vaults.key(for: server))
        XCTAssertEqual(vaults.state(of: server), .failed("Server nicht erreichbar."))
        XCTAssertEqual(status.message, "Server nicht erreichbar.")
        // The note waits, unbound and unsent.
        XCTAssertEqual(try store.meta(for: note.id).dirty, true)
        XCTAssertNil(store.boundAccount())
        XCTAssertNil(store.sealedKey())
    }

    func testTheRestingStatusSaysWhatSyncWaitsFor() {
        let sessions = ServerSessions(registry: registry, status: status)
        let vaults = VaultSessions(sessions: sessions, status: status)
        let coordinator = SyncCoordinator(registry: registry, sessions: sessions, vaults: vaults, library: library, status: status)
        XCTAssertEqual(coordinator.statusAtRest, "Der Abgleich wartet auf den Tresor.")
        XCTAssertEqual(SyncCoordinator.waitingForVault(.serverTooOld), "Der Server kann noch nicht verschlüsseln. Der Abgleich ruht bis zum Update.")
    }
}
