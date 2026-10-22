import InkhashCore
import KennelKit
import XCTest
@testable import Inkhash

/// Syncing reports to the Kennel overview; an unreachable Kennel sends nothing and says so (ADR 0077).
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

    private func coordinator(_ overview: KennelOverview) -> SyncCoordinator {
        let sessions = ServerSessions(registry: registry, status: status)
        let vaults = VaultSessions(sessions: sessions, status: status)
        return SyncCoordinator(registry: registry, sessions: sessions, vaults: vaults, library: library, status: status, overview: overview)
    }

    func testAnUnreachableKennelSendsNothingAndSaysSo() async throws {
        var note = Note.newText(now: "2026-10-01T08:00:00Z")
        note.applyMarkdown("# Lokal\n")
        library.add(note)
        let overview = KennelOverview()
        let coordinator = coordinator(overview)
        XCTAssertTrue(coordinator.isEnabled)
        await coordinator.sync()
        XCTAssertEqual(overview.state.phase, .unreachable)
        XCTAssertEqual(overview.state.status, .unreachable)
        // The note waits, unbound and unsent.
        XCTAssertEqual(try store.meta(for: note.id).dirty, true)
        XCTAssertNil(store.boundAccount())
    }

    func testPlacesFollowLinksAndMoves() {
        let overview = KennelOverview()
        var workspace = registry.current
        XCTAssertEqual(overview.place(of: workspace), .synced)
        overview.remotes = [RemoteWorkspace(id: APIClient.mainWorkspace, name: "Privat", move: RemoteMove(to: nil, state: "running"))]
        XCTAssertEqual(overview.place(of: workspace), .moving)
        workspace.link = nil
        XCTAssertEqual(overview.place(of: workspace), .here)
        XCTAssertEqual(overview.storage(of: overview.remotes[0])?.name, "Mein Speicher")
    }

    func testTheRestingStatusSaysWhereAWorkspaceLies() {
        let coordinator = coordinator(KennelOverview())
        XCTAssertEqual(coordinator.statusAtRest, "")
        registry.setLink(registry.current.id, to: nil)
        XCTAssertEqual(coordinator.statusAtRest, StatusLine.localOnly)
    }
}
