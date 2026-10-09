import Foundation

/// The notes of one workspace on the server, as they lie there: plain or sealed. `APIClient`
/// is the one for the network. See ADR 0052.
public protocol SealedWire: Sendable {
    func changes(after cursor: Int) async throws -> ChangePage
    func fetchWire(id: UUID) async throws -> WireNote
    func putSealed(_ upload: SealedUpload, baseRevision: Int) async throws -> WireNote
    func deleteWire(id: UUID, baseRevision: Int) async throws -> WireNote
    func putBlob(sha256: String, data: Data) async throws
    func fetchBlob(sha256: String) async throws -> Data
}

extension APIClient: SealedWire {}

/// Notes and blobs through a vault key: everything goes up sealed, sealed notes come back open.
/// Plain notes from before the vault still come back as they are and are remembered, so the
/// sync puts them up again sealed. Blob names on the server come from `Sealer.blobName`; a blob
/// that is not there under its sealed name is looked for under its plain one, from before.
public final class SealedTransport: NoteTransport, @unchecked Sendable {
    private let wire: any SealedWire
    private let sealer: Sealer
    private let lock = NSLock()
    private var plain: Set<UUID> = []

    public init(wire: any SealedWire, sealer: Sealer) {
        self.wire = wire
        self.sealer = sealer
    }

    public func changes(after cursor: Int) async throws -> ChangePage {
        try await wire.changes(after: cursor)
    }

    public func fetchNote(id: UUID) async throws -> Note {
        let stored = try await wire.fetchWire(id: id)
        remember(stored)
        return try sealer.open(stored)
    }

    public func putNote(_ note: Note, baseRevision: Int) async throws -> Note {
        let upload = try sealer.seal(note)
        do {
            let stored = try await wire.putSealed(upload, baseRevision: baseRevision)
            remember(stored)
            return try sealer.open(stored)
        } catch let APIError.sealedConflict(sealed) {
            throw APIError.conflict(try sealer.open(sealed))
        }
    }

    public func deleteNote(id: UUID, baseRevision: Int) async throws -> Note {
        do {
            let stored = try await wire.deleteWire(id: id, baseRevision: baseRevision)
            remember(stored)
            return try sealer.open(stored)
        } catch let APIError.sealedConflict(sealed) {
            throw APIError.conflict(try sealer.open(sealed))
        }
    }

    public func putBlob(sha256: String, data: Data) async throws {
        try await wire.putBlob(sha256: sealer.blobName(sha256), data: try sealer.sealBlob(data, plain: sha256))
    }

    public func fetchBlob(sha256: String) async throws -> Data {
        do {
            return try sealer.openBlob(try await wire.fetchBlob(sha256: sealer.blobName(sha256)), plain: sha256)
        } catch APIError.notFound {
            // Uploaded before the vault, still plain.
            let data = try await wire.fetchBlob(sha256: sha256)
            guard sha256Hex(data) == sha256 else { throw SealError.wrongBlob }
            return data
        }
    }

    public func unsealedNotes() async -> Set<UUID> {
        lock.withLock { plain }
    }

    private func remember(_ stored: WireNote) {
        lock.withLock {
            switch stored {
            case .plain(let note): _ = plain.insert(note.id)
            case .sealed(let sealed): plain.remove(sealed.id)
            }
        }
    }
}
