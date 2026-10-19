import Foundation

public enum RegistrationMode: String, Codable, Sendable {
    case setup
    case closed
}

/// What Kennel says about itself. The app syncs only with a Kennel that runs the module `inkhash` (ADR 0067).
public struct ServerHealth: Codable, Equatable, Sendable {
    public var ok: Bool
    public var registration: RegistrationMode
    /// `kennel`. Nil for anything else, e.g. the old inkhashd.
    public var server: String?
    /// The server's release.
    public var version: String?
    /// Switched-on modules and what each can do.
    public var modules: [String: ModuleInfo]?
    /// True when the server redeems join codes at `POST /v1/join` (ADR 0071).
    public var join: Bool?

    public init(ok: Bool, registration: RegistrationMode, server: String? = nil, version: String? = nil, modules: [String: ModuleInfo]? = nil, join: Bool? = nil) {
        self.ok = ok
        self.registration = registration
        self.server = server
        self.version = version
        self.modules = modules
        self.join = join
    }

    /// The module of this app, nil if the server does not run it.
    public var inkhash: ModuleInfo? { modules?[APIClient.module] }

    /// True when the server keeps vaults for inkhash (ADR 0052). Kennel's module always does.
    public var vault: Bool { inkhash?.vault == true }
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

    public init(title: String? = nil, encryption: String? = nil, vault: Bool? = nil, workspaces: Bool? = nil, pairing: Bool? = nil, appScheme: String? = nil) {
        self.title = title
        self.encryption = encryption
        self.vault = vault
        self.workspaces = workspaces
        self.pairing = pairing
        self.appScheme = appScheme
    }
}

public struct ServerAccount: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
}

public struct ServerSession: Codable, Equatable, Sendable {
    public var token: String
    public var account: ServerAccount
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

    public init(id: String, name: String, symbol: String? = nil, icon: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.icon = icon
        self.updatedAt = updatedAt
    }
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

public struct APIClient: NoteTransport, Sendable {
    /// The workspace every account has. Its notes are also served without the workspace prefix.
    public static let mainWorkspace = "main"
    /// This app's module on Kennel.
    public static let module = "inkhash"
    /// Where the module's routes live. Signing in, sessions and passwords stay in Kennel's core under `/v1`.
    public static let appPrefix = "/v1/apps/\(module)"

    public var baseURL: URL
    public var token: String
    public var session: URLSession
    /// Workspace on the server the note routes go to. See ADR 0020.
    public var workspace: String

    public init(baseURL: URL, token: String, workspace: String = APIClient.mainWorkspace, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.workspace = workspace
        self.session = session
    }

    /// `main` keeps the routes without `/workspaces/{ws}`.
    private var notePrefix: String {
        workspace == Self.mainWorkspace ? Self.appPrefix : "\(Self.appPrefix)/workspaces/\(workspace)"
    }

    /// Servers before workspaces answer 404; they only have `main`.
    public func workspaces() async throws -> [RemoteWorkspace] {
        try await workspaceList().workspaces
    }

    public func workspaceList() async throws -> RemoteWorkspaceList {
        do {
            let data = try await send(url: try endpoint("\(Self.appPrefix)/workspaces"), method: "GET", body: nil, contentType: nil)
            return try InkhashJSON.decode(RemoteWorkspaceList.self, from: data)
        } catch APIError.notFound {
            return RemoteWorkspaceList(workspaces: [RemoteWorkspace(id: Self.mainWorkspace, name: "Privat")], ordered: nil)
        }
    }

    public func createWorkspace(name: String) async throws -> RemoteWorkspace {
        let data = try await send(
            url: try endpoint("\(Self.appPrefix)/workspaces"),
            method: "POST",
            body: try InkhashJSON.encode(["name": name]),
            contentType: "application/json"
        )
        return try InkhashJSON.decode(RemoteWorkspace.self, from: data)
    }

    public func updateWorkspace(id: String, look: WorkspaceLook) async throws -> RemoteWorkspace {
        // `icon` goes out as null to remove a picture, so it is written by hand.
        var body: [String: Any] = ["name": look.name, "symbol": look.symbol]
        body["icon"] = look.icon ?? NSNull()
        let data = try await send(
            url: try endpoint("\(Self.appPrefix)/workspaces/\(id)"),
            method: "PATCH",
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            contentType: "application/json"
        )
        return try InkhashJSON.decode(RemoteWorkspace.self, from: data)
    }

    /// Deletes a workspace on the server, for every device. `main` cannot be deleted. See ADR 0045.
    public func deleteWorkspace(id: String) async throws {
        _ = try await send(url: try endpoint("\(Self.appPrefix)/workspaces/\(id)"), method: "DELETE", body: nil, contentType: nil)
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
            url: try endpoint("\(Self.appPrefix)/workspace-order"),
            method: "PUT",
            body: try InkhashJSON.encode(["ids": ids]),
            contentType: "application/json"
        )
        return try InkhashJSON.decode(RemoteWorkspaceList.self, from: data)
    }

    public func changes(after cursor: Int) async throws -> ChangePage {
        let url = try endpoint("\(notePrefix)/changes", query: [URLQueryItem(name: "after", value: String(cursor))])
        let data = try await send(url: url, method: "GET", body: nil, contentType: nil)
        return try InkhashJSON.decode(ChangePage.self, from: data)
    }

    public func fetchNote(id: UUID) async throws -> Note {
        let data = try await send(url: try endpoint("\(notePrefix)/notes/\(id.uuidString.lowercased())"), method: "GET", body: nil, contentType: nil)
        return try InkhashJSON.decode(Note.self, from: data)
    }

    public func putNote(_ note: Note, baseRevision: Int) async throws -> Note {
        struct Body: Encodable {
            var baseRevision: Int
            var note: Note
        }
        let payload = try InkhashJSON.encode(Body(baseRevision: baseRevision, note: note))
        let data = try await send(
            url: try endpoint("\(notePrefix)/notes/\(note.id.uuidString.lowercased())"),
            method: "PUT",
            body: payload,
            contentType: "application/json"
        )
        return try InkhashJSON.decode(Note.self, from: data)
    }

    public func deleteNote(id: UUID, baseRevision: Int) async throws -> Note {
        let url = try endpoint("\(notePrefix)/notes/\(id.uuidString.lowercased())", query: [URLQueryItem(name: "baseRevision", value: String(baseRevision))])
        let data = try await send(url: url, method: "DELETE", body: nil, contentType: nil)
        return try InkhashJSON.decode(Note.self, from: data)
    }

    public func putBlob(sha256: String, data: Data) async throws {
        _ = try await send(
            url: try endpoint("\(notePrefix)/blobs/\(sha256)"),
            method: "PUT",
            body: data,
            contentType: "application/octet-stream"
        )
    }

    public func fetchBlob(sha256: String) async throws -> Data {
        try await send(url: try endpoint("\(notePrefix)/blobs/\(sha256)"), method: "GET", body: nil, contentType: nil)
    }

    // MARK: Vault, ADR 0052

    /// The account's vault, or nil while it has none.
    public func vault() async throws -> VaultRecord? {
        do {
            let data = try await send(url: try endpoint("\(Self.appPrefix)/vault"), method: "GET", body: nil, contentType: nil)
            return try InkhashJSON.decode(VaultRecord.self, from: data)
        } catch APIError.notFound {
            return nil
        }
    }

    /// Creates the vault, or rewraps it under the same key. Another key there is `vaultExists`.
    public func putVault(_ record: VaultRecord) async throws -> VaultRecord {
        var sent = record
        sent.epoch = nil
        let data = try await send(url: try endpoint("\(Self.appPrefix)/vault"), method: "PUT", body: try InkhashJSON.encode(sent), contentType: "application/json")
        return try InkhashJSON.decode(VaultRecord.self, from: data)
    }

    /// Resets the vault with the login password: the account's notes on the server are moved away.
    public func resetVault(password: String) async throws {
        do {
            _ = try await send(
                url: try endpoint("\(Self.appPrefix)/vault"), method: "DELETE",
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
            url: try endpoint("\(Self.appPrefix)/vault/pairings/\(id.uuidString.lowercased())"), method: "PUT",
            body: try InkhashJSON.encode(PairingBody(sealed: sealed)), contentType: "application/json"
        )
    }

    /// Takes the sealed account key off the server. Nil if it expired, was taken or withdrawn.
    public func takePairing(_ id: UUID) async throws -> String? {
        do {
            let data = try await send(url: try endpoint("\(Self.appPrefix)/vault/pairings/\(id.uuidString.lowercased())"), method: "GET", body: nil, contentType: nil)
            return try InkhashJSON.decode(PairingBody.self, from: data).sealed
        } catch APIError.notFound {
            return nil
        }
    }

    public func withdrawPairing(_ id: UUID) async throws {
        _ = try await send(url: try endpoint("\(Self.appPrefix)/vault/pairings/\(id.uuidString.lowercased())"), method: "DELETE", body: nil, contentType: nil)
    }

    // MARK: Notes as they lie on the server

    public func fetchWire(id: UUID) async throws -> WireNote {
        let data = try await send(url: try endpoint("\(notePrefix)/notes/\(id.uuidString.lowercased())"), method: "GET", body: nil, contentType: nil)
        return try InkhashJSON.decode(WireNote.self, from: data)
    }

    public func putSealed(_ upload: SealedUpload, baseRevision: Int) async throws -> WireNote {
        struct Body: Encodable {
            var baseRevision: Int
            var note: SealedUpload
        }
        let data = try await send(
            url: try endpoint("\(notePrefix)/notes/\(upload.id.uuidString.lowercased())"),
            method: "PUT",
            body: try InkhashJSON.encode(Body(baseRevision: baseRevision, note: upload)),
            contentType: "application/json"
        )
        return try InkhashJSON.decode(WireNote.self, from: data)
    }

    public func deleteWire(id: UUID, baseRevision: Int) async throws -> WireNote {
        let url = try endpoint("\(notePrefix)/notes/\(id.uuidString.lowercased())", query: [URLQueryItem(name: "baseRevision", value: String(baseRevision))])
        let data = try await send(url: url, method: "DELETE", body: nil, contentType: nil)
        return try InkhashJSON.decode(WireNote.self, from: data)
    }

    public func probe() async throws -> ServerHealth {
        let health = try await self.health()
        if !token.isEmpty {
            _ = try await changes(after: 0)
        }
        return health
    }

    public func health() async throws -> ServerHealth {
        let data = try await send(url: try endpoint("/v1/health"), method: "GET", body: nil, contentType: nil, authorize: false)
        return try InkhashJSON.decode(ServerHealth.self, from: data)
    }

    public func openSession(name: String, password: String) async throws -> ServerSession {
        let payload = try InkhashJSON.encode(Credentials(name: name, password: password))
        let data = try await send(
            url: try endpoint("/v1/session"),
            method: "POST",
            body: payload,
            contentType: "application/json",
            authorize: false
        )
        return try InkhashJSON.decode(ServerSession.self, from: data)
    }

    /// Redeems a join code (ADR 0071). Without `name` and `password` a device code opens a session
    /// of its account; an invite then throws `JoinError.needsAccount`, and with both it creates the
    /// account. An unusable code is `APIError.unauthorized`, a taken name `JoinError.nameTaken`.
    public func join(code: String, name: String? = nil, password: String? = nil) async throws -> ServerSession {
        var body = ["code": code]
        if let name, let password {
            body["name"] = name
            body["password"] = password
        }
        do {
            let data = try await send(
                url: try endpoint("/v1/join"),
                method: "POST",
                body: try InkhashJSON.encode(body),
                contentType: "application/json",
                authorize: false
            )
            return try InkhashJSON.decode(ServerSession.self, from: data)
        } catch let APIError.badStatus(400, answer) where name == nil && Self.reason(of: answer).map(["name", "password"].contains) == true {
            throw JoinError.needsAccount
        } catch let APIError.badStatus(409, answer) where Self.error(of: answer) == "name-taken" {
            throw JoinError.nameTaken
        }
    }

    private struct ErrorBody: Decodable {
        var error: String?
        var reason: String?
    }

    private static func reason(of body: String) -> String? {
        (try? JSONDecoder().decode(ErrorBody.self, from: Data(body.utf8)))?.reason
    }

    private static func error(of body: String) -> String? {
        (try? JSONDecoder().decode(ErrorBody.self, from: Data(body.utf8)))?.error
    }

    /// Changes the account's own password. Its other sessions end, this one stays. See ADR 0050.
    public func changePassword(current: String, to password: String) async throws {
        let payload = try InkhashJSON.encode(["current": current, "password": password])
        do {
            _ = try await send(url: try endpoint("/v1/password"), method: "PUT", body: payload, contentType: "application/json")
        } catch let APIError.badStatus(code, body) where code == 403 && body.contains("wrong-password") {
            throw APIError.wrongPassword
        }
    }

    public func logout() async throws {
        _ = try await send(url: try endpoint("/v1/session"), method: "DELETE", body: nil, contentType: nil)
    }

    private struct Credentials: Encodable {
        var name: String
        var password: String
    }

    private func send(url: URL, method: String, body: Data?, contentType: String?, authorize: Bool = true) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if authorize {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 404 { throw APIError.notFound }
        if http.statusCode == 429 { throw APIError.slowDown }
        if http.statusCode == 409 {
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
        guard (200...299).contains(http.statusCode) else {
            throw APIError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func endpoint(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        var basePath = components.path
        if basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidResponse }
        return url
    }
}
