import CryptoKit
import XCTest
@testable import InkhashCore

/// Few rounds: the tests check the construction, not the cost.
let testRounds = 1_000

final class VaultTests: XCTestCase {
    func testCreatedVaultOpensWithItsPassphraseOnly() throws {
        let (key, record) = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: testRounds)
        XCTAssertEqual(key.material.count, 32)
        XCTAssertEqual(record.keyId, key.keyId)
        XCTAssertEqual(record.kdf.name, "pbkdf2-sha256")
        XCTAssertEqual(record.kdf.rounds, testRounds)
        XCTAssertEqual(Data(base64Encoded: record.kdf.salt)?.count, 16)
        XCTAssertEqual(try VaultCrypto.open(record, passphrase: "korrekt pferd batterie"), key)
        XCTAssertThrowsError(try VaultCrypto.open(record, passphrase: "korrekt pferd batterlE")) {
            XCTAssertEqual($0 as? VaultError, .wrongPassphrase)
        }
    }

    func testDefaultsAreTheDocumentedOnes() {
        XCTAssertEqual(VaultCrypto.rounds, 600_000)
        XCTAssertEqual(Passphrase.minimum, 12)
    }

    func testRewrapKeepsTheKeyWithANewPassphrase() throws {
        let (key, old) = try VaultCrypto.create(passphrase: "erste passphrase", rounds: testRounds)
        let new = try VaultCrypto.wrap(key, passphrase: "zweite passphrase", rounds: testRounds)
        XCTAssertEqual(new.keyId, old.keyId)
        XCTAssertNotEqual(new.kdf.salt, old.kdf.salt)
        XCTAssertEqual(try VaultCrypto.open(new, passphrase: "zweite passphrase"), key)
        XCTAssertThrowsError(try VaultCrypto.open(new, passphrase: "erste passphrase"))
    }

    func testPassphraseIsNormalizedLikeAnyKeyboardTypesIt() throws {
        let composed = "grüne wiese im mai"
        let decomposed = "gru\u{0308}ne wiese im mai"
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))
        let (key, record) = try VaultCrypto.create(passphrase: composed, rounds: testRounds)
        XCTAssertEqual(try VaultCrypto.open(record, passphrase: decomposed), key)
    }

    func testTheWrappedKeyIsBoundToItsId() throws {
        let (_, record) = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: testRounds)
        var moved = record
        moved.keyId = UUID().uuidString.lowercased()
        XCTAssertThrowsError(try VaultCrypto.open(moved, passphrase: "korrekt pferd batterie"))
    }

    func testEpochComesFromTheServer() throws {
        var (_, record) = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: testRounds)
        record.epoch = 3
        XCTAssertEqual(try VaultCrypto.open(record, passphrase: "korrekt pferd batterie").epoch, 3)
    }

    func testUnknownOrBrokenVaultsAreRefused() throws {
        var (_, record) = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: testRounds)
        var other = record
        other.kdf.name = "scrypt"
        XCTAssertThrowsError(try VaultCrypto.open(other, passphrase: "korrekt pferd batterie")) { XCTAssertEqual($0 as? VaultError, .unsupported) }
        record.wrapped = "AAAA"
        XCTAssertThrowsError(try VaultCrypto.open(record, passphrase: "korrekt pferd batterie")) { XCTAssertEqual($0 as? VaultError, .unsupported) }
    }

    func testWeakPassphrasesAreRefused() {
        XCTAssertEqual(Passphrase.problem("kurz"), "Die Passphrase braucht mindestens 12 Zeichen.")
        XCTAssertEqual(Passphrase.problem("aaaaaaaaaaaaaaaa"), "Die Passphrase ist zu eintönig.")
        XCTAssertNil(Passphrase.problem("korrekt pferd batterie"))
        XCTAssertEqual(Passphrase.problem("korrekt pferd batterie", repeated: "korrekt pferd"), "Die Wiederholung passt nicht.")
        XCTAssertThrowsError(try VaultCrypto.create(passphrase: "kurz", rounds: testRounds)) { XCTAssertEqual($0 as? VaultError, .weakPassphrase) }
    }

    func testRecordRoundTripsThroughJSON() throws {
        let (_, record) = try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: testRounds)
        let decoded = try InkhashJSON.decode(VaultRecord.self, from: InkhashJSON.encode(record))
        XCTAssertEqual(decoded, record)
    }
}

final class SealerTests: XCTestCase {
    private func sealer() throws -> Sealer {
        Sealer(try VaultCrypto.create(passphrase: "korrekt pferd batterie", rounds: testRounds).0)
    }

    private func note() -> Note {
        var note = Note.newText(now: "2026-10-01T08:00:00Z")
        note.applyMarkdown("# Geheim\nnur für mich #privat\n")
        note.folder = "Tagebuch"
        note.favorite = true
        note.revision = 7
        return note
    }

    func testANoteRoundTripsAndTakesTheServersRevision() throws {
        let sealer = try sealer()
        let original = note()
        let upload = try sealer.seal(original)
        XCTAssertFalse(upload.deleted)
        XCTAssertFalse(upload.sealed.contains("Geheim"))
        let stored = SealedNote(id: original.id, revision: 9, updatedAt: "2026-10-09T10:00:00Z", deletedAt: nil, sealed: upload.sealed)
        let opened = try sealer.open(stored)
        XCTAssertTrue(opened.sameContent(as: original))
        XCTAssertEqual(opened.createdAt, original.createdAt)
        XCTAssertEqual(opened.revision, 9)
        XCTAssertEqual(opened.updatedAt, "2026-10-09T10:00:00Z")
    }

    func testSameContentGivesTheSameBytesSoRetriesMatch() throws {
        let sealer = try sealer()
        var first = note()
        var second = first
        second.revision = 99
        second.updatedAt = "2030-01-01T00:00:00Z"
        XCTAssertEqual(try sealer.seal(first).sealed, try sealer.seal(second).sealed)
        first.applyMarkdown("# Geheim\nanders\n")
        XCTAssertNotEqual(try sealer.seal(first).sealed, try sealer.seal(second).sealed)
    }

    func testDeletedNotesSayTheyAreDeleted() throws {
        var trashed = note()
        trashed.deletedAt = "2026-10-02T08:00:00Z"
        let upload = try sealer().seal(trashed)
        XCTAssertTrue(upload.deleted)
        let key = try sealer()
        let opened = try key.open(SealedNote(id: trashed.id, revision: 1, updatedAt: "x", deletedAt: "2026-10-03T08:00:00Z", sealed: try key.seal(trashed).sealed))
        XCTAssertEqual(opened.deletedAt, "2026-10-03T08:00:00Z")
    }

    func testContentCannotMoveToAnotherNote() throws {
        let sealer = try sealer()
        let original = note()
        let upload = try sealer.seal(original)
        let swapped = SealedNote(id: UUID(), revision: 1, updatedAt: "x", deletedAt: nil, sealed: upload.sealed)
        XCTAssertThrowsError(try sealer.open(swapped))
    }

    func testAnotherKeyCannotOpen() throws {
        let original = note()
        let upload = try sealer().seal(original)
        let stored = SealedNote(id: original.id, revision: 1, updatedAt: "x", deletedAt: nil, sealed: upload.sealed)
        XCTAssertThrowsError(try sealer().open(stored)) { XCTAssertEqual($0 as? SealError, .damaged) }
    }

    func testTamperingIsDetected() throws {
        let sealer = try sealer()
        let original = note()
        var bytes = try XCTUnwrap(Data(base64Encoded: sealer.seal(original).sealed))
        bytes[bytes.count / 2] ^= 0x01
        let stored = SealedNote(id: original.id, revision: 1, updatedAt: "x", deletedAt: nil, sealed: bytes.base64EncodedString())
        XCTAssertThrowsError(try sealer.open(stored))
    }

    func testInkNotesKeepPagesAndElements() throws {
        let sealer = try sealer()
        var page = InkPage(blob: String(repeating: "a", count: 64), transcript: "Skizze #berg", tags: ["berg"])
        page.elements = [PageElement(kind: .link, x: 1, y: 2, width: 3, height: 4, link: "https://inkhash.app")]
        var ink = Note.newInk(page: page, now: "2026-10-01T08:00:00Z")
        ink.paper = Paper(color: "#FAF5E8", pattern: .grid, spacing: 32)
        let stored = SealedNote(id: ink.id, revision: 1, updatedAt: "x", deletedAt: nil, sealed: try sealer.seal(ink).sealed)
        XCTAssertTrue(try sealer.open(stored).sameContent(as: ink))
    }

    func testBlobsRoundTripUnderANameOnlyTheKeyMakes() throws {
        let sealer = try sealer()
        let data = Data("striche".utf8)
        let plain = sha256Hex(data)
        let name = sealer.blobName(plain)
        XCTAssertEqual(name.count, 64)
        XCTAssertNotEqual(name, plain)
        XCTAssertEqual(name, sealer.blobName(plain))
        XCTAssertNotEqual(name, try self.sealer().blobName(plain))
        let sealed = try sealer.sealBlob(data, plain: plain)
        XCTAssertNotEqual(sha256Hex(sealed), name, "the server must not take it for plain")
        XCTAssertEqual(try sealer.sealBlob(data, plain: plain), sealed)
        XCTAssertEqual(try sealer.openBlob(sealed, plain: plain), data)
        XCTAssertEqual(try sealer.openBlob(sealed, name: name), data)
        XCTAssertThrowsError(try sealer.openBlob(sealed, plain: sha256Hex(Data("anders".utf8))))
    }

    func testWireNotesDecodeByVersion() throws {
        let sealed = Data(#"{"schemaVersion":2,"id":"6F1C3A2E-7B64-4D1A-9C3E-2A8B0D5E7F10","revision":3,"updatedAt":"t","deletedAt":null,"sealed":"AAAA"}"#.utf8)
        guard case .sealed(let note) = try InkhashJSON.decode(WireNote.self, from: sealed) else { return XCTFail("expected sealed") }
        XCTAssertEqual(note.revision, 3)
        XCTAssertEqual(note.id, UUID(uuidString: "6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10"))
        let plain = try InkhashJSON.encode(Note.newText(now: "2026-10-01T08:00:00Z"))
        guard case .plain = try InkhashJSON.decode(WireNote.self, from: plain) else { return XCTFail("expected plain") }
    }

    func testUploadEncodesTheWireForm() throws {
        let id = UUID()
        let json = try JSONSerialization.jsonObject(with: InkhashJSON.encode(SealedUpload(id: id, sealed: "AAAA", deleted: true))) as? [String: Any]
        XCTAssertEqual(json?["schemaVersion"] as? Int, 2)
        XCTAssertEqual(json?["id"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(json?["sealed"] as? String, "AAAA")
        XCTAssertEqual(json?["deleted"] as? Bool, true)
    }

    @MainActor
    func testBindingKeyCountsResets() {
        XCTAssertEqual(Workspaces.bindingKey(accountID: "a", remote: "main"), "a")
        XCTAssertEqual(Workspaces.bindingKey(accountID: "a", remote: "w", epoch: 0), "a/w")
        XCTAssertEqual(Workspaces.bindingKey(accountID: "a", remote: "main", epoch: 2), "a#2")
    }
}
