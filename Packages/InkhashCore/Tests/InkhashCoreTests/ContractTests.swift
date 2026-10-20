import KennelKit
import XCTest
@testable import InkhashCore

/// The Swift client against a real Kennel with the module inkhash, started by
/// `tools/contract-test.sh`. Skipped without it. See ADR 0067. Each test uses accounts of its own on the shared server.
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
            token = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["token"] as? String)
        } else {
            token = try await KennelClient(address: url).signIn(name: "admin", password: "adminadmin").token
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
        let session = try await KennelClient(address: url).signIn(name: name, password: "secretsecret")
        return APIClient(session: session)
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
        let health = try await KennelClient(address: url).health()
        XCTAssertTrue(health.vault)
        XCTAssertTrue(health.isKennel)
        XCTAssertTrue(health.join)
        XCTAssertEqual(health.inkhash?.appScheme, "inkhash")
        XCTAssertEqual(health.registrationMode, .closed)
    }

    /// A join code made by `token`, as Kennel's admin page makes it. See ADR 0071.
    private func joinCode(_ kind: String, by token: String) async throws -> JoinCode {
        var request = URLRequest(url: url.appendingPathComponent("v1/join-codes"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["kind": kind])
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 201)
        let raw = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String)
        return try XCTUnwrap(JoinCode(raw))
    }

    func testDeviceCodeOpensASessionOfTheSameAccount() async throws {
        let first = try await account()
        let code = try await joinCode("device", by: first.token)
        // Read the way a person types it: lowercase, no dashes.
        let typed = try XCTUnwrap(JoinCode(code.description.lowercased().replacingOccurrences(of: "-", with: "")))
        let session = try await KennelClient(address: url).join(code: typed)
        XCTAssertNotEqual(session.token, first.token)
        XCTAssertNotNil(ServerAddress.accountID(session.account.id))
        _ = try await APIClient(session: session).workspaceList()
        do {
            _ = try await KennelClient(address: url).join(code: code)
            XCTFail("a code is good once")
        } catch {
            XCTAssertEqual(error as? KennelError, .unauthorized)
        }
    }

    func testAppMakesADeviceCodeAndRevokesAnother() async throws {
        let first = try await account()
        let issued = try await first.kennel.issueJoinCode(.device)
        XCTAssertEqual(issued.kind, .device)
        XCTAssertGreaterThan(issued.expiresAt, Date())
        let link = try XCTUnwrap(issued.joinLink(on: url))
        let target = try XCTUnwrap(JoinLink.parse(link.absoluteString, appScheme: "inkhash"))
        let session = try await KennelClient(address: target.address).join(code: try XCTUnwrap(target.code))
        _ = try await APIClient(session: session).workspaceList()

        let withdrawn = try await first.kennel.issueJoinCode(.device)
        try await first.kennel.revokeJoinCode(withdrawn.id)
        do {
            _ = try await KennelClient(address: url).join(code: withdrawn.code)
            XCTFail("a withdrawn code is no good")
        } catch {
            XCTAssertEqual(error as? KennelError, .unauthorized)
        }
        do {
            try await first.kennel.revokeJoinCode(withdrawn.id)
            XCTFail("withdrawn twice")
        } catch {
            XCTAssertEqual((error as? KennelError)?.status, 404)
        }
    }

    func testInviteAsksForAnAccountThenCreatesIt() async throws {
        let code = try await joinCode("invite", by: adminToken)
        let open = KennelClient(address: url)
        do {
            _ = try await open.join(code: code)
            XCTFail("an invite needs name and password")
        } catch {
            XCTAssertEqual(error as? KennelJoinError, .needsAccount)
        }
        do {
            _ = try await open.join(code: code, account: KennelNewAccount(name: "admin", password: "secretsecret"))
            XCTFail("the name is taken")
        } catch {
            XCTAssertEqual(error as? KennelJoinError, .nameTaken)
        }
        let name = "i" + UUID().uuidString.prefix(8).lowercased()
        let session = try await open.join(code: code, account: KennelNewAccount(name: name, password: "secretsecret"))
        XCTAssertEqual(session.account.name, name)
        _ = try await open.signIn(name: name, password: "secretsecret")
    }

    func testNotesNeedAVaultAndASecondDeviceReadsThem() async throws {
        let client = try await account()
        let store = try freshStore()
        let notes = try fill(store)
        // Kennel takes no plain notes, with or without a vault.
        do {
            _ = try await client.putNote(notes[0], baseRevision: 0)
            XCTFail("plain note accepted")
        } catch let APIError.badStatus(code, body) {
            XCTAssertEqual(code, 400)
            XCTAssertTrue(body.contains("sealed"))
        }

        // The vault, then the first sync, sealed.
        let none = try await client.vault()
        XCTAssertNil(none)
        let recoveryKey = RecoveryKey.generate()
        let (key, record) = try VaultCrypto.create(recoveryKey: recoveryKey, rounds: Self.rounds)
        let stored = try await client.putVault(record)
        XCTAssertEqual(stored.keyId, key.keyId)
        XCTAssertEqual(stored.epoch, 0)
        let sealer = Sealer(key)
        let report = try await Syncer.sync(store: store, transport: SealedTransport(wire: client, sealer: sealer), sealedWith: key.keyId)
        XCTAssertEqual(report.rejected, [])
        XCTAssertEqual(store.sealedKey(), key.keyId)
        var trashed = try XCTUnwrap(store.note(id: notes[2].id))
        trashed.deletedAt = "2026-10-02T08:00:00Z"
        try store.save(note: trashed, meta: LocalMeta(dirty: true, conflict: false))
        _ = try await Syncer.sync(store: store, transport: SealedTransport(wire: client, sealer: sealer), sealedWith: key.keyId)
        for note in notes {
            guard case .sealed(let sealed) = try await client.fetchWire(id: note.id) else { return XCTFail("plain on the server: \(note.id)") }
            XCTAssertEqual(sealed.deletedAt != nil, note.id == notes[2].id)
        }
        for name in try XCTUnwrap(store.note(id: notes[1].id)?.pages?.first).blobNames {
            _ = try await client.fetchBlob(sha256: sealer.blobName(name))
        }
        // A plain write is refused with a vault too.
        do {
            _ = try await client.putNote(Note.newText(now: "2026-10-03T08:00:00Z"), baseRevision: 0)
            XCTFail("plain note accepted")
        } catch let APIError.badStatus(code, body) {
            XCTAssertEqual(code, 400)
            XCTAssertTrue(body.contains("sealed"))
        }

        // A second device opens the vault with the recovery key and reads everything.
        let vault = try await client.vault()
        let fetched = try XCTUnwrap(vault)
        XCTAssertThrowsError(try VaultCrypto.open(fetched, recoveryKey: .generate()))
        let opened = try VaultCrypto.open(fetched, recoveryKey: recoveryKey)
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
        let (key, record) = try VaultCrypto.create(recoveryKey: .generate(), rounds: Self.rounds)
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
        let (key, record) = try VaultCrypto.create(recoveryKey: .generate(), rounds: Self.rounds)
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

    func testNewRecoveryKeyPairingAndReset() async throws {
        let client = try await account()
        let (key, record) = try VaultCrypto.create(recoveryKey: .generate(), rounds: Self.rounds)
        _ = try await client.putVault(record)
        let store = try freshStore()
        _ = try fill(store)
        _ = try await Syncer.sync(store: store, transport: SealedTransport(wire: client, sealer: Sealer(key)), sealedWith: key.keyId)

        // A new recovery key for the same key.
        let second = RecoveryKey.generate()
        _ = try await client.putVault(try VaultCrypto.wrap(key, recoveryKey: second, rounds: Self.rounds))
        let vault = try await client.vault()
        let rewrapped = try XCTUnwrap(vault)
        XCTAssertEqual(try VaultCrypto.open(rewrapped, recoveryKey: second), key)

        // Pairing: the key goes through the server once, sealed with the code's secret.
        let pairing = Pairing.make()
        try await client.offerPairing(pairing.id, sealed: try pairing.seal(key))
        let scanned = try Pairing(code: pairing.code)
        let taken = try await client.takePairing(scanned.id)
        XCTAssertEqual(try scanned.open(try XCTUnwrap(taken)), key)
        let again = try await client.takePairing(scanned.id)
        XCTAssertNil(again)
        // A withdrawn pairing is gone, a newer one replaces the older.
        let withdrawn = Pairing.make()
        try await client.offerPairing(withdrawn.id, sealed: try withdrawn.seal(key))
        try await client.withdrawPairing(withdrawn.id)
        let none = try await client.takePairing(withdrawn.id)
        XCTAssertNil(none)
        let older = Pairing.make(), newer = Pairing.make()
        try await client.offerPairing(older.id, sealed: try older.seal(key))
        try await client.offerPairing(newer.id, sealed: try newer.seal(key))
        let replaced = try await client.takePairing(older.id)
        XCTAssertNil(replaced)
        let current = try await client.takePairing(newer.id)
        XCTAssertNotNil(current)

        // Another key cannot take over.
        let (_, intruder) = try VaultCrypto.create(recoveryKey: .generate(), rounds: Self.rounds)
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
        let (fresh, freshRecord) = try VaultCrypto.create(recoveryKey: .generate(), rounds: Self.rounds)
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
            try await client.kennel.changePassword(current: "falschfalsch", to: "neuesneues")
            XCTFail("expected wrongPassword")
        } catch KennelPasswordError.wrongPassword {}
        try await client.kennel.changePassword(current: "secretsecret", to: "neuesneues")
        _ = try await client.workspaceList()
    }

    /// A plain workspace in a storage of its own: no vault, notes as they are, a second device reads them (ADR 0075).
    func testPlainWorkspaceInItsOwnStorageNeedsNoVault() async throws {
        let client = try await account()
        let health = try await client.kennel.health()
        XCTAssertEqual(health.inkhash?.choosesWorkspaceStorage, true)

        // The admin's NAS for inkhash; another one only for Xoot stays out of the app's list.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("inkhash-share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let admin = KennelClient(address: url, token: adminToken)
        let share = try await admin.createStorage(
            KennelNewStorage(name: "NAS", driver: "folder", settings: ["path": .string(folder.path)], household: true, modules: ["inkhash"]))
        _ = try await admin.createStorage(
            KennelNewStorage(name: "Fotos", driver: "folder", settings: ["path": .string(folder.path)], household: true, modules: ["xoot"]))
        let offered = try await client.noteStorages()
        XCTAssertTrue(offered.contains { $0.id == share.id })
        XCTAssertFalse(offered.contains { $0.name == "Fotos" })

        let remote = try await client.createWorkspace(name: "Haushalt", as: NewRemoteWorkspace(sealed: false, storageID: share.id))
        XCTAssertFalse(remote.isSealed)
        XCTAssertEqual(remote.storageId, share.id)
        var scoped = client
        scoped.workspace = remote.id
        let none = try await client.vault()
        XCTAssertNil(none)

        let store = try freshStore()
        let notes = try fill(store)
        let report = try await Syncer.sync(store: store, transport: scoped)
        XCTAssertEqual(report.rejected, [])
        for note in notes {
            guard case .plain = try await scoped.fetchWire(id: note.id) else { return XCTFail("sealed on the server: \(note.id)") }
        }
        let other = try freshStore()
        _ = try await Syncer.sync(store: other, transport: scoped)
        for note in notes {
            let mine = try XCTUnwrap(store.note(id: note.id))
            let theirs = try XCTUnwrap(other.note(id: note.id))
            XCTAssertTrue(theirs.sameContent(as: mine))
        }
        for name in try XCTUnwrap(other.note(id: notes[1].id)?.pages?.first).blobNames {
            XCTAssertEqual(try other.blob(name), try store.blob(name))
        }
        // Readable on the share itself.
        let listed = try FileManager.default.subpathsOfDirectory(atPath: folder.appendingPathComponent("inkhash").path)
        XCTAssertTrue(listed.contains { $0.contains("/\(remote.id)/notes/") })

        // A sealed note is refused there.
        let key = try VaultCrypto.create(recoveryKey: .generate(), rounds: Self.rounds).0
        do {
            _ = try await SealedTransport(wire: scoped, sealer: Sealer(key)).putNote(Note.newText(now: "2026-10-03T08:00:00Z"), baseRevision: 0)
            XCTFail("sealed note accepted")
        } catch let APIError.badStatus(code, body) {
            XCTAssertEqual(code, 400)
            XCTAssertTrue(body.contains("plain"))
        }
    }

}
