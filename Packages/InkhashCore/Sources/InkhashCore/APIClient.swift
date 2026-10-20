import Foundation
import KennelKit

public enum RegistrationMode: String, Codable, Sendable {
    case setup
    case closed

    /// Kennel's `registration`; anything but `setup` is closed.
    public init(kennel value: String?) {
        self = value == "setup" ? .setup : .closed
    }
}

/// What Kennel's `/v1/health` says for this app. The app syncs only with a Kennel that runs the module `inkhash`
/// (ADR 0067, 0073).
extension KennelHealth {
    /// The module of this app, nil if Kennel does not run it.
    public var inkhash: ModuleInfo? { module(APIClient.module, as: ModuleInfo.self) }

    /// True when Kennel keeps vaults for inkhash (ADR 0052). Kennel's module always does.
    public var vault: Bool { inkhash?.vault == true }

    public var registrationMode: RegistrationMode { RegistrationMode(kennel: registration) }
}

/// One module in `/v1/health`: its title and the capabilities the app asks for instead of versions.
public struct ModuleInfo: Codable, Equatable, Sendable {
    public var title: String?
    public var encryption: String?
    public var vault: Bool?
    public var workspaces: Bool?
    public var pairing: Bool?
    /// The URL scheme of the module's app, `inkhash`, for Kennel's page `/join` (ADR 0071).
    public var appScheme: String?
    /// Workspaces may be made without encryption (ADR 0075, Kennel ADR 0026).
    public var plainWorkspaces: Bool?
    /// Workspaces may be made in a storage of their own (ADR 0075, Kennel ADR 0026).
    public var workspaceStorage: Bool?

    public init(
        title: String? = nil, encryption: String? = nil, vault: Bool? = nil, workspaces: Bool? = nil, pairing: Bool? = nil,
        appScheme: String? = nil, plainWorkspaces: Bool? = nil, workspaceStorage: Bool? = nil
    ) {
        self.title = title
        self.encryption = encryption
        self.vault = vault
        self.workspaces = workspaces
        self.pairing = pairing
        self.appScheme = appScheme
        self.plainWorkspaces = plainWorkspaces
        self.workspaceStorage = workspaceStorage
    }

    /// Whether a new server workspace can choose its storage and encryption.
    public var choosesWorkspaceStorage: Bool { plainWorkspaces == true && workspaceStorage == true }
}

public struct RemoteWorkspace: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// SF Symbol name. Nil until a device has set the look, and on servers before ADR 0043.
    public var symbol: String?
    /// sha256 of the picture in the workspace's blobs.
    public var icon: String?
    /// Last change of the look. Nil while no device has set it.
    public var updatedAt: String?
    /// Whether its notes are encrypted. Nil from a Kennel before ADR 0075, where every workspace is.
    public var sealed: Bool?
    /// The Kennel storage it lies in; nil: the account's storage for inkhash.
    public var storageId: String?

    public init(
        id: String, name: String, symbol: String? = nil, icon: String? = nil, updatedAt: String? = nil, sealed: Bool? = nil,
        storageId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.icon = icon
        self.updatedAt = updatedAt
        self.sealed = sealed
        self.storageId = storageId
    }

    /// Encrypted unless the server says otherwise (ADR 0075).
    public var isSealed: Bool { sealed ?? true }
}

/// How a new workspace lies on the server, chosen once (ADR 0075). The default is what every workspace was before.
public struct NewRemoteWorkspace: Hashable, Sendable {
    public var sealed: Bool
    /// A Kennel storage that allows inkhash; nil: the account's storage.
    public var storageID: String?

    public init(sealed: Bool = true, storageID: String? = nil) {
        self.sealed = sealed
        self.storageID = storageID
    }

    public static let standard = NewRemoteWorkspace()
}

/// The account's workspaces in its order. See ADR 0043.
public struct RemoteWorkspaceList: Codable, Equatable, Sendable {
    public var workspaces: [RemoteWorkspace]
    /// Whether the account has stored an order. Nil on servers that keep neither order nor look.
    public var ordered: Bool?

    public init(workspaces: [RemoteWorkspace], ordered: Bool?) {
        self.workspaces = workspaces
        self.ordered = ordered
    }

    /// Servers from before ADR 0043 know only names; their workspaces have no look to sync.
    public var keepsLooks: Bool { ordered != nil }
}

/// What a device sends when its look of a workspace changed.
public struct WorkspaceLook: Equatable, Sendable {
    public var name: String
    public var symbol: String
    public var icon: String?

    public init(name: String, symbol: String, icon: String?) {
        self.name = name
        self.symbol = symbol
        self.icon = icon
    }
}

/// The routes of Kennel's module `inkhash` with one session (ADR 0067). Kennel's core (sessions, join codes, passwords)
/// is `kennel`, from KennelKit (ADR 0073).
public struct APIClient: NoteTransport, Sendable {
    /// The workspace every account has. Its notes are also served without the workspace prefix.
    public static let mainWorkspace = "main"
    /// This app's module on Kennel.
    public static let module = "inkhash"
    /// Where the module's routes live. Signing in, sessions and passwords stay in Kennel's core under `/v1`.
    public static let appPrefix = "/v1/apps/\(module)"

    /// Kennel's core with the same session.
    public let kennel: KennelClient
    /// Workspace on the server the note routes go to. See ADR 0020.
    public var workspace: String

    public var baseURL: URL { kennel.address }
    public var token: String { kennel.token ?? "" }

    /// `session` defaults to KennelKit's shared ephemeral one.
    public init(baseURL: URL, token: String, workspace: String = APIClient.mainWorkspace, session: URLSession? = nil) {
        kennel = KennelClient(address: baseURL, token: token.isEmpty ? nil : token, urlSession: session)
        self.workspace = workspace
    }

    public init(session: KennelSession, workspace: String = APIClient.mainWorkspace, urlSession: URLSession? = nil) {
        self.init(baseURL: session.address, token: session.token, workspace: workspace, session: urlSession)
    }

    /// `main` keeps the routes without `/workspaces/{ws}`.
    private var notePrefix: String {
        workspace == Self.mainWorkspace ? "" : "/workspaces/\(workspace)"
    }

    /// Servers before workspaces answer 404; they only have `main`.
    public func workspaces() async throws -> [RemoteWorkspace] {
        try await workspaceList().workspaces
    }

    public func workspaceList() async throws -> RemoteWorkspaceList {
        do {
            let data = try await send("/workspaces", method: "GET")
            return try InkhashJSON.decode(RemoteWorkspaceList.self, from: data)
        } catch APIError.notFound {
            return RemoteWorkspaceList(workspaces: [RemoteWorkspace(id: Self.mainWorkspace, name: "Privat")], ordered: nil)
        }
    }

    /// The standard choice sends only the name, so older servers take it as before.
    public func createWorkspace(name: String, as choice: NewRemoteWorkspace = .standard) async throws -> RemoteWorkspace {
        struct Body: Encodable {
            var name: String
            var sealed: Bool?
            var storageId: String?
        }
        let body = Body(name: name, sealed: choice.sealed ? nil : false, storageId: choice.storageID)
        let data = try await send(
            "/workspaces",
            method: "POST",
            body: try InkhashJSON.encode(body),
            contentType: "application/json"
        )
        return try InkhashJSON.decode(RemoteWorkspace.self, from: data)
    }

    /// Kennel's storages that inkhash may use for notes (Kennel ADR 0025): they allow the module and hold blobs.
    public func noteStorages() async throws -> [KennelStorage] {
        try await kennel.storages(for: Self.module).filter { $0.kinds.contains("blobs") }
    }

    public func updateWorkspace(id: String, look: WorkspaceLook) async throws -> RemoteWorkspace {
        // `icon` goes out as null to remove a picture, so it is written by hand.
        var body: [String: Any] = ["name": look.name, "symbol": look.symbol]
        body["icon"] = look.icon ?? NSNull()
        let data = try await send(
            "/workspaces/\(id)",
            method: "PATCH",
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            contentType: "application/json"
        )
        return try InkhashJSON.decode(RemoteWorkspace.self, from: data)
    }

    /// Deletes a workspace on the server, for every device. `main` cannot be deleted. See ADR 0045.
    public func deleteWorkspace(id: String) async throws {
        _ = try await send("/workspaces/\(id)", method: "DELETE")
    }

    /// How many notes outside the trash a workspace on the server holds, read from its change log.
    public func noteCount(workspace remote: String) async throws -> Int {
        var scoped = self
        scoped.workspace = remote
        var living: [UUID: Bool] = [:]
        var cursor = 0
        var page: ChangePage
        repeat {
            page = try await scoped.changes(after: cursor)
            for change in page.changes { living[change.noteId] = !change.deleted }
            if page.hasMore && page.cursor <= cursor { throw APIError.invalidResponse }
            cursor = page.cursor
        } while page.hasMore
        return living.values.filter { $0 }.count
    }

    public func orderWorkspaces(ids: [String]) async throws -> RemoteWorkspaceList {
        let data = try await send(
            "/workspace-order",
            method: "PUT",
            body: try InkhashJSON.encode(["ids": ids]),
            contentType: "application/json"
        )
        return try InkhashJSON.decode(RemoteWorkspaceList.self, from: data)
    }

    public func changes(after cursor: Int) async throws -> ChangePage {
        let (route, query) = ("\(notePrefix)/changes", [URLQueryItem(name: "after", value: String(cursor))])
        let data = try await send(route, query: query, method: "GET")
        return try InkhashJSON.decode(ChangePage.self, from: data)
    }

    public func fetchNote(id: UUID) async throws -> Note {
        let data = try await send("\(notePrefix)/notes/\(id.uuidString.lowercased())", method: "GET")
        return try InkhashJSON.decode(Note.self, from: data)
    }

    public func putNote(_ note: Note, baseRevision: Int) async throws -> Note {
        struct Body: Encodable {
            var baseRevision: Int
            var note: Note
        }
        let payload = try InkhashJSON.encode(Body(baseRevision: baseRevision, note: note))
        let data = try await send(
            "\(notePrefix)/notes/\(note.id.uuidString.lowercased())",
            method: "PUT",
            body: payload,
            contentType: "application/json"
        )
        return try InkhashJSON.decode(Note.self, from: data)
    }

    public func deleteNote(id: UUID, baseRevision: Int) async throws -> Note {
        let (route, query) = ("\(notePrefix)/notes/\(id.uuidString.lowercased())", [URLQueryItem(name: "baseRevision", value: String(baseRevision))])
        let data = try await send(route, query: query, method: "DELETE")
        return try InkhashJSON.decode(Note.self, from: data)
    }

    public func putBlob(sha256: String, data: Data) async throws {
        _ = try await send(
            "\(notePrefix)/blobs/\(sha256)",
            method: "PUT",
            body: data,
            contentType: "application/octet-stream"
        )
    }

    public func fetchBlob(sha256: String) async throws -> Data {
        try await send("\(notePrefix)/blobs/\(sha256)", method: "GET")
    }

    // MARK: Vault, ADR 0052

    /// The account's vault, or nil while it has none.
    public func vault() async throws -> VaultRecord? {
        do {
            let data = try await send("/vault", method: "GET")
            return try InkhashJSON.decode(VaultRecord.self, from: data)
        } catch APIError.notFound {
            return nil
        }
    }

    /// Creates the vault, or rewraps it under the same key. Another key there is `vaultExists`.
    public func putVault(_ record: VaultRecord) async throws -> VaultRecord {
        var sent = record
        sent.epoch = nil
        let data = try await send("/vault", method: "PUT", body: try InkhashJSON.encode(sent), contentType: "application/json")
        return try InkhashJSON.decode(VaultRecord.self, from: data)
    }

    /// Resets the vault with the login password: the account's notes on the server are moved away.
    public func resetVault(password: String) async throws {
        do {
            _ = try await send(
                "/vault", method: "DELETE",
                body: try InkhashJSON.encode(["password": password]), contentType: "application/json"
            )
        } catch let APIError.badStatus(code, body) where code == 403 && body.contains("wrong-password") {
            throw APIError.wrongPassword
        }
    }

    // MARK: Pairing, ADR 0054

    private struct PairingBody: Codable {
        var sealed: String
    }

    /// Leaves the sealed account key on the server for five minutes, replacing an open pairing.
    public func offerPairing(_ id: UUID, sealed: String) async throws {
        _ = try await send(
            "/vault/pairings/\(id.uuidString.lowercased())", method: "PUT",
            body: try InkhashJSON.encode(PairingBody(sealed: sealed)), contentType: "application/json"
        )
    }

    /// Takes the sealed account key off the server. Nil if it expired, was taken or withdrawn.
    public func takePairing(_ id: UUID) async throws -> String? {
        do {
            let data = try await send("/vault/pairings/\(id.uuidString.lowercased())", method: "GET")
            return try InkhashJSON.decode(PairingBody.self, from: data).sealed
        } catch APIError.notFound {
            return nil
        }
    }

    public func withdrawPairing(_ id: UUID) async throws {
        _ = try await send("/vault/pairings/\(id.uuidString.lowercased())", method: "DELETE")
    }

    // MARK: Notes as they lie on the server

    public func fetchWire(id: UUID) async throws -> WireNote {
        let data = try await send("\(notePrefix)/notes/\(id.uuidString.lowercased())", method: "GET")
        return try InkhashJSON.decode(WireNote.self, from: data)
    }

    public func putSealed(_ upload: SealedUpload, baseRevision: Int) async throws -> WireNote {
        struct Body: Encodable {
            var baseRevision: Int
            var note: SealedUpload
        }
        let data = try await send(
            "\(notePrefix)/notes/\(upload.id.uuidString.lowercased())",
            method: "PUT",
            body: try InkhashJSON.encode(Body(baseRevision: baseRevision, note: upload)),
            contentType: "application/json"
        )
        return try InkhashJSON.decode(WireNote.self, from: data)
    }

    public func deleteWire(id: UUID, baseRevision: Int) async throws -> WireNote {
        let (route, query) = ("\(notePrefix)/notes/\(id.uuidString.lowercased())", [URLQueryItem(name: "baseRevision", value: String(baseRevision))])
        let data = try await send(route, query: query, method: "DELETE")
        return try InkhashJSON.decode(WireNote.self, from: data)
    }

    /// A module route, its answer mapped to `APIError`. No answer at all stays `KennelError.unreachable`.
    private func send(_ route: String, query: [URLQueryItem] = [], method: String, body: Data? = nil, contentType: String = "application/json") async throws -> Data {
        let answer = try await kennel.module(Self.module).response(method, route, query: query, body: body, contentType: contentType)
        let data = answer.body
        if answer.status == 401 { throw APIError.unauthorized }
        if answer.status == 404 { throw APIError.notFound }
        if answer.status == 429 { throw APIError.slowDown }
        if answer.status == 409 {
            struct ConflictEnvelope: Decodable { var note: WireNote }
            struct VaultEnvelope: Decodable { var vault: VaultRecord }
            if let envelope = try? InkhashJSON.decode(ConflictEnvelope.self, from: data) {
                switch envelope.note {
                case .plain(let note): throw APIError.conflict(note)
                case .sealed(let sealed): throw APIError.sealedConflict(sealed)
                }
            }
            if let envelope = try? InkhashJSON.decode(VaultEnvelope.self, from: data) {
                throw APIError.vaultExists(envelope.vault)
            }
            throw APIError.badStatus(409, String(data: data, encoding: .utf8) ?? "")
        }
        guard answer.isSuccess else {
            throw APIError.badStatus(answer.status, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
