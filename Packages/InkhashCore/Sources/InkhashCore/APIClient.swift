import Foundation

public enum RegistrationMode: String, Codable, Sendable {
    case setup
    case closed
}

public struct ServerHealth: Codable, Equatable, Sendable {
    public var ok: Bool
    public var registration: RegistrationMode
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

    /// `main` keeps the old unprefixed routes, so it also works against servers without workspaces.
    private var notePrefix: String {
        workspace == Self.mainWorkspace ? "/v1" : "/v1/workspaces/\(workspace)"
    }

    /// Servers before workspaces answer 404; they only have `main`.
    public func workspaces() async throws -> [RemoteWorkspace] {
        try await workspaceList().workspaces
    }

    public func workspaceList() async throws -> RemoteWorkspaceList {
        do {
            let data = try await send(url: try endpoint("/v1/workspaces"), method: "GET", body: nil, contentType: nil)
            return try InkhashJSON.decode(RemoteWorkspaceList.self, from: data)
        } catch APIError.notFound {
            return RemoteWorkspaceList(workspaces: [RemoteWorkspace(id: Self.mainWorkspace, name: "Privat")], ordered: nil)
        }
    }

    public func createWorkspace(name: String) async throws -> RemoteWorkspace {
        let data = try await send(
            url: try endpoint("/v1/workspaces"),
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
            url: try endpoint("/v1/workspaces/\(id)"),
            method: "PATCH",
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            contentType: "application/json"
        )
        return try InkhashJSON.decode(RemoteWorkspace.self, from: data)
    }

    public func orderWorkspaces(ids: [String]) async throws -> RemoteWorkspaceList {
        let data = try await send(
            url: try endpoint("/v1/workspace-order"),
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
            struct ConflictEnvelope: Decodable { var note: Note }
            if let envelope = try? InkhashJSON.decode(ConflictEnvelope.self, from: data) {
                throw APIError.conflict(envelope.note)
            }
            throw APIError.badStatus(409, "")
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
