import CryptoKit
import Foundation

/// A note as the server keeps it once the account has a vault: only what syncing needs is plain.
/// See ADR 0052 and API.md.
public struct SealedNote: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: UUID
    public var revision: Int
    public var updatedAt: String
    public var deletedAt: String?
    public var sealed: String

    public init(id: UUID, revision: Int, updatedAt: String, deletedAt: String?, sealed: String) {
        self.schemaVersion = 2
        self.id = id
        self.revision = revision
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sealed = sealed
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, revision, updatedAt, deletedAt, sealed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard let id = UUID(uuidString: try container.decode(String.self, forKey: .id)) else { throw InkhashError.invalidID }
        self.id = id
        revision = try container.decode(Int.self, forKey: .revision)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)
        sealed = try container.decode(String.self, forKey: .sealed)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(revision, forKey: .revision)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(sealed, forKey: .sealed)
    }
}

/// What a device sends to store a sealed note. `deleted` keeps or makes it a tombstone.
public struct SealedUpload: Encodable, Equatable, Sendable {
    public var schemaVersion = 2
    public var id: UUID
    public var sealed: String
    public var deleted: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, sealed, deleted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(sealed, forKey: .sealed)
        try container.encode(deleted, forKey: .deleted)
    }
}

/// A note on the wire: plain from before the vault, or sealed.
public enum WireNote: Decodable, Equatable, Sendable {
    case plain(Note)
    case sealed(SealedNote)

    private enum Probe: String, CodingKey {
        case schemaVersion
    }

    public init(from decoder: Decoder) throws {
        let probe = try decoder.container(keyedBy: Probe.self)
        if try probe.decode(Int.self, forKey: .schemaVersion) == 2 {
            self = .sealed(try SealedNote(from: decoder))
        } else {
            self = .plain(try Note(from: decoder))
        }
    }

    public var id: UUID {
        switch self {
        case .plain(let note): note.id
        case .sealed(let sealed): sealed.id
        }
    }
}

public enum SealError: Error, Equatable {
    case damaged
    case wrongNote
    case wrongBlob
}

/// Encrypts and decrypts notes and blobs with an account key. Deterministic: the same content
/// gives the same bytes, so the server's retry check still works. See ADR 0052.
public struct Sealer: Sendable {
    public let keyId: String
    private let content: SymmetricKey
    private let nonces: SymmetricKey
    private let names: SymmetricKey
    static let format: UInt8 = 1

    public init(_ key: VaultKey) {
        keyId = key.keyId
        let master = SymmetricKey(data: key.material)
        let salt = Data("inkhash-v1".utf8)
        content = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: salt, info: Data("content".utf8), outputByteCount: 32)
        nonces = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: salt, info: Data("nonce".utf8), outputByteCount: 32)
        names = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: salt, info: Data("blob-name".utf8), outputByteCount: 32)
    }

    // MARK: Notes

    /// The note's content, without what the server sets, packed and encrypted.
    public func seal(_ note: Note) throws -> SealedUpload {
        var content = note
        content.revision = 0
        content.updatedAt = ""
        content.deletedAt = nil
        let json = try InkhashJSON.encode(content)
        guard let packed = try? (json as NSData).compressed(using: .zlib) as Data else { throw SealError.damaged }
        let box = try encrypt(packed, aad: Self.noteAAD(note.id), nonceInput: Data("note:".utf8) + Self.noteAAD(note.id) + json)
        return SealedUpload(id: note.id, sealed: box.base64EncodedString(), deleted: note.deletedAt != nil)
    }

    /// The note in `sealed`, with revision, timestamps and tombstone from the server.
    public func open(_ sealed: SealedNote) throws -> Note {
        guard let box = Data(base64Encoded: sealed.sealed) else { throw SealError.damaged }
        let packed = try decrypt(box, aad: Self.noteAAD(sealed.id))
        guard let json = try? (packed as NSData).decompressed(using: .zlib) as Data else { throw SealError.damaged }
        var note = try InkhashJSON.decode(Note.self, from: json)
        guard note.id == sealed.id else { throw SealError.wrongNote }
        note.revision = sealed.revision
        note.updatedAt = sealed.updatedAt
        note.deletedAt = sealed.deletedAt
        return note
    }

    /// A wire note as a note: sealed ones are opened, plain ones from before the vault pass.
    public func open(_ wire: WireNote) throws -> Note {
        switch wire {
        case .plain(let note): note
        case .sealed(let sealed): try open(sealed)
        }
    }

    // MARK: Blobs

    /// The name of a blob on the server, from its plain SHA-256. Only key holders can make it.
    public func blobName(_ plain: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data("blob:\(plain)".utf8), using: names)
            .map { String(format: "%02x", $0) }.joined()
    }

    public func sealBlob(_ data: Data, plain: String) throws -> Data {
        try encrypt(data, aad: Self.blobAAD(blobName(plain)), nonceInput: Data("blob:\(plain)".utf8))
    }

    /// Decrypts a blob fetched under `name`. The caller checks the plain hash when it knows it.
    public func openBlob(_ data: Data, name: String) throws -> Data {
        try decrypt(data, aad: Self.blobAAD(name))
    }

    /// Decrypts a blob and checks that it is the one asked for.
    public func openBlob(_ data: Data, plain: String) throws -> Data {
        let opened = try openBlob(data, name: blobName(plain))
        guard sha256Hex(opened) == plain else { throw SealError.wrongBlob }
        return opened
    }

    // MARK: Private

    private static func noteAAD(_ id: UUID) -> Data {
        Data("inkhash-note-v1:\(id.uuidString.lowercased())".utf8)
    }

    private static func blobAAD(_ name: String) -> Data {
        Data("inkhash-blob-v1:\(name)".utf8)
    }

    /// AES-256-GCM with a synthetic nonce: an HMAC over what identifies the plaintext.
    private func encrypt(_ plaintext: Data, aad: Data, nonceInput: Data) throws -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: nonceInput, using: nonces)
        let nonce = try AES.GCM.Nonce(data: Data(mac).prefix(12))
        let box = try AES.GCM.seal(plaintext, using: content, nonce: nonce, authenticating: aad)
        guard let combined = box.combined else { throw SealError.damaged }
        return Data([Self.format]) + combined
    }

    private func decrypt(_ data: Data, aad: Data) throws -> Data {
        guard data.first == Self.format, data.count > 1 + 12 + 16 else { throw SealError.damaged }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst())
            return try AES.GCM.open(box, using: content, authenticating: aad)
        } catch {
            throw SealError.damaged
        }
    }
}
