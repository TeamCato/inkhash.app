import XCTest
@testable import InkhashCore

/// The Swift client against the real server, started by `tools/contract-test.sh`. Skipped
/// without it. Each test uses accounts of its own on the shared server.
@MainActor
final class ContractTests: XCTestCase {
    private static let rounds = 100_000
    private var url: URL!
    private var adminToken: String!

    override func setUp() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["INKHASH_CONTRACT_URL"], let url = URL(string: raw) else {
            throw XCTSkip("no server; run make contract-test")
        }
        self.url = url
        adminToken = try await Self.admin(url: url, setupToken: env["INKHASH_CONTRACT_SETUP"] ?? "")
    }

    /// The first test sets the server up; the others sign in as the same admin.
    private static var cachedAdmin: String?

    private static func admin(url: URL, setupToken: String) async throws -> String {
        if let cachedAdmin { return cachedAdmin }
        var request = URLRequest(url: url.appendingPathComponent("v1/setup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["setupToken": setupToken, "name": "admin", "password": "adminadmin"])
        let (data, response) = try await URLSession.shared.data(for: request)
        let token: String
        if (response as? HTTPURLResponse)?.statusCode == 201 {
            token = try InkhashJSON.decode(ServerSession.self, from: data).token
        } else {
            token = try await APIClient(baseURL: url, token: "").openSession(name: "admin", password: "adminadmin").token
        }
        cachedAdmin = token
        return token
    }

    /// A new account, signed in like the app does.
    private func account() async throws -> APIClient {
        let name = "u" + UUID().uuidString.prefix(8).lowercased()
        var request = URLRequest(url: url.appendingPathComponent("v1/accounts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(adminToken!)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "password": "secretsecret"])
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 201)
        let session = try await APIClient(baseURL: url, token: "").openSession(name: name, password: "secretsecret")
        return APIClient(baseURL: url, token: session.token)
    }

    private func freshStore() throws -> LocalStore {
        try LocalStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    /// A text note, an ink note with a photo, a note in the trash.
    private func fill(_ store: LocalStore) throws -> [Note] {
        var text = Note.newText(now: "2026-10-01T08:00:00Z")
        text.applyMarkdown("# Vertrag\nGeheim #privat\n")
        text.folder = "Projekt/Treffen"
        var page = InkPage(blob: try store.putBlob(Data("strokes \(UUID())".utf8)), transcript: "Skizze #berg", tags: ["berg"])
        page.elements = [PageElement(kind: .image, x: 100, y: 100, width: 50, height: 50, blob: try store.putBlob(Data("jpeg \(UUID())".utf8)))]
        var ink = Note.newInk(page: page, now: "2026-10-01T08:00:00Z")
        ink.transcript = "Skizze #berg"
        ink.tags = ["berg"]
        var trashed = Note.newText(now: "2026-10-01T08:00:00Z")
        trashed.applyMarkdown("# Weg\n")
        for note in [text, ink, trashed] { try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false)) }
        return [text, ink, trashed]
    }

    func testHealthSaysVault() async throws {
        let health = try await APIClient(baseURL: url, token: "").health()
        XCTAssertEqual(health.vault, true)
    }

    func testAPlainAccountMovesToItsVaultAndASecondDeviceReadsIt() async throws {
        let client = try await account()
        let store = try freshStore()
        let notes = try fill(store)
        // Before the vault: an app from before syncs plain, then trashes one note.
        _ = try await Syncer.sync(store: store, transport: client)
        var trashed = try XCTUnwrap(store.note(id: notes[2].id))
        trashed.deletedAt = "2026-10-02T08:00:00Z"
        try store.save(note: trashed, meta: LocalMeta(dirty: true, conflict: false))
        _ = try await Syncer.sync(store: store, transport: client)
        guard case .plain = try await client.fetchWire(id: notes[0].id) else { return XCTFail("expected plain") }

        // The vault, then the move.
        let none = try await client.vault()
        XCTAssertNil(none)
        let (key, record) = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: Self.rounds)
        let stored = try await client.putVault(record)
        XCTAssertEqual(stored.keyId, key.keyId)
        XCTAssertEqual(stored.epoch, 0)
        let sealer = Sealer(key)
        let report = try await Syncer.sync(store: store, transport: SealedTransport(wire: client, sealer: sealer), sealedWith: key.keyId)
        XCTAssertEqual(report.rejected, [])
        XCTAssertEqual(store.sealedKey(), key.keyId)
        for note in notes {
            guard case .sealed(let sealed) = try await client.fetchWire(id: note.id) else { return XCTFail("still plain: \(note.id)") }
            XCTAssertEqual(sealed.deletedAt != nil, note.id == notes[2].id)
        }
        // Plain blobs are gone from the server; sealed ones are there.
        for name in try XCTUnwrap(store.note(id: notes[1].id)?.pages?.first).blobNames {
            do {
                _ = try await client.fetchBlob(sha256: name)
                XCTFail("plain blob still there")
            } catch APIError.notFound {}
            _ = try await client.fetchBlob(sha256: sealer.blobName(name))
        }
        // A plain write is refused now.
        do {
            _ = try await client.putNote(Note.newText(now: "2026-10-03T08:00:00Z"), baseRevision: 0)
            XCTFail("plain note accepted")
        } catch let APIError.badStatus(code, body) {
            XCTAssertEqual(code, 400)
            XCTAssertTrue(body.contains("sealed"))
        }

        // A second device opens the vault with the passphrase and reads everything.
        let vault = try await client.vault()
        let fetched = try XCTUnwrap(vault)
        XCTAssertThrowsError(try VaultCrypto.open(fetched, passphrase: "falsche passphrase"))
        let opened = try VaultCrypto.open(fetched, passphrase: "korrekt pferd batterie")
        let other = try freshStore()
        _ = try await Syncer.sync(store: other, transport: SealedTransport(wire: client, sealer: Sealer(opened)), sealedWith: opened.keyId)
        for note in notes {
            let mine = try XCTUnwrap(store.note(id: note.id))
            let theirs = try XCTUnwrap(other.note(id: note.id))
            XCTAssertTrue(theirs.sameContent(as: mine))
            XCTAssertEqual(theirs.revision, mine.revision)
        }
        for name in try XCTUnwrap(other.note(id: notes[1].id)?.pages?.first).blobNames {
            XCTAssertEqual(try other.blob(name), try store.blob(name))
        }
    }

    func testEditsConflictsAndRetriesWithSealedNotes() async throws {
        let client = try await account()
        let (key, record) = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: Self.rounds)
        _ = try await client.putVault(record)
        let transport = SealedTransport(wire: client, sealer: Sealer(key))
        let a = try freshStore()
        let b = try freshStore()
        let notes = try fill(a)
        _ = try await Syncer.sync(store: a, transport: transport, sealedWith: key.keyId)
        _ = try await Syncer.sync(store: b, transport: transport, sealedWith: key.keyId)

        // Both change the same note; the second one to sync sees a conflict with the first one's words.
        for (store, words) in [(a, "von A"), (b, "von B")] {
            var note = try XCTUnwrap(store.note(id: notes[0].id))
            note.applyMarkdown("# Vertrag\n\(words)\n")
            try store.save(note: note, meta: LocalMeta(dirty: true, conflict: false))
        }
        _ = try await Syncer.sync(store: a, transport: transport, sealedWith: key.keyId)
        let report = try await Syncer.sync(store: b, transport: transport, sealedWith: key.keyId)
        XCTAssertEqual(report.conflicts, 1)
        XCTAssertEqual(try b.conflictNote(id: notes[0].id)?.markdown, "# Vertrag\nvon A\n")

        // A retry of the same sealed content after a lost answer is no conflict.
        let current = try XCTUnwrap(a.note(id: notes[0].id))
        let upload = try Sealer(key).seal(current)
        let again = try await client.putSealed(upload, baseRevision: current.revision - 1)
        guard case .sealed(let same) = again else { return XCTFail("expected sealed") }
        XCTAssertEqual(same.revision, current.revision)
    }

    func testAPictureOfAWorkspaceGoesUpSealed() async throws {
        let client = try await account()
        let (key, record) = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: Self.rounds)
        _ = try await client.putVault(record)
        let sealer = Sealer(key)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let icon = try Workspaces.saveIcon(Data("png \(UUID())".utf8), base: base)
        let server = UUID()
        var home = Workspace(name: "Zuhause", symbol: "house", icon: icon, link: WorkspaceLink(server: server, remote: "main"))
        home.lookPending = true
        _ = try await LookSyncer.sync(
            DeviceSetup(servers: [], workspaces: [home], current: home.id), server: server, base: base,
            transport: SealedLooks(inner: client, sealer: sealer, icons: [icon])
        )
        let listed = try await client.workspaceList()
        XCTAssertEqual(listed.workspaces.first { $0.id == "main" }?.icon, sealer.blobName(icon))

        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let there = Workspace(name: "Privat", link: WorkspaceLink(server: server, remote: "main"))
        let synced = try await LookSyncer.sync(
            DeviceSetup(servers: [], workspaces: [there], current: there.id), server: server, base: other,
            transport: SealedLooks(inner: client, sealer: sealer, icons: [])
        )
        XCTAssertEqual(synced.workspaces[0].icon, icon)
        XCTAssertEqual(synced.workspaces[0].name, "Zuhause")
    }

    func testPassphraseChangeAndReset() async throws {
        let client = try await account()
        let (key, record) = try VaultCrypto.create(passphrase: "erste passphrase", rounds: Self.rounds)
        _ = try await client.putVault(record)
        let store = try freshStore()
        _ = try fill(store)
        _ = try await Syncer.sync(store: store, transport: SealedTransport(wire: client, sealer: Sealer(key)), sealedWith: key.keyId)

        // A new passphrase for the same key.
        _ = try await client.putVault(try VaultCrypto.wrap(key, passphrase: "zweite passphrase", rounds: Self.rounds))
        let vault = try await client.vault()
        let rewrapped = try XCTUnwrap(vault)
        XCTAssertEqual(try VaultCrypto.open(rewrapped, passphrase: "zweite passphrase"), key)

        // Another key cannot take over.
        let (_, intruder) = try VaultCrypto.create(passphrase: "fremde passphrase", rounds: Self.rounds)
        do {
            _ = try await client.putVault(intruder)
            XCTFail("expected vaultExists")
        } catch let APIError.vaultExists(existing) {
            XCTAssertEqual(existing.keyId, key.keyId)
        }

        // Forgotten: reset with the login password, then a new vault in the next epoch.
        do {
            try await client.resetVault(password: "falschfalsch")
            XCTFail("expected wrongPassword")
        } catch APIError.wrongPassword {}
        try await client.resetVault(password: "secretsecret")
        let gone = try await client.vault()
        XCTAssertNil(gone)
        let (fresh, freshRecord) = try VaultCrypto.create(passphrase: "dritte passphrase", rounds: Self.rounds)
        let stored = try await client.putVault(freshRecord)
        XCTAssertEqual(stored.epoch, 1)
        let page = try await client.changes(after: 0)
        XCTAssertTrue(page.changes.isEmpty)

        // The device binds anew and sends its notes again under the new key.
        let freshKey = VaultKey(keyId: fresh.keyId, material: fresh.material, epoch: stored.epoch ?? 0)
        try Library.bind(store, to: Workspaces.bindingKey(accountID: "x", remote: "main", epoch: freshKey.epoch))
        let report = try await Syncer.sync(store: store, transport: SealedTransport(wire: client, sealer: Sealer(freshKey)), sealedWith: freshKey.keyId)
        XCTAssertEqual(report.pushed, 3)
        XCTAssertEqual(store.sealedKey(), freshKey.keyId)
    }

    func testOwnPasswordChange() async throws {
        let client = try await account()
        do {
            try await client.changePassword(current: "falschfalsch", to: "neuesneues")
            XCTFail("expected wrongPassword")
        } catch APIError.wrongPassword {}
        try await client.changePassword(current: "secretsecret", to: "neuesneues")
        _ = try await client.workspaceList()
    }
}
