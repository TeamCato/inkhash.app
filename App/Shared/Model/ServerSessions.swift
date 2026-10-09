import Foundation
import InkhashCore
import Observation

/// What the app knows about the address typed into the server form.
enum ServerConnection: Equatable {
    case unknown
    case checking
    case reachable(RegistrationMode)
    case failed(String)
}

/// Sessions with the servers of this device: signing in and out, tokens in the keychain,
/// expired sessions, and checking an address while it is typed. See ADR 0016 and 0020.
@MainActor
@Observable
final class ServerSessions {
    var connection: ServerConnection = .unknown
    /// Servers whose session the server rejected. Shows a notice until signing in or dismissing it.
    private(set) var expired: Set<UUID>
    /// Session tokens by server. A server without one is signed out.
    private var tokens: [UUID: String] = [:]
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    private let registry: WorkspaceRegistry
    private let status: StatusLine

    private static let expiredKey = "inkhash.expiredServers"
    private static let invalidAddress = "Die Adresse braucht http oder https und einen Host."

    init(registry: WorkspaceRegistry, status: StatusLine) {
        self.registry = registry
        self.status = status
        expired = Set((UserDefaults.standard.stringArray(forKey: Self.expiredKey) ?? []).compactMap(UUID.init(uuidString:)))
        if let migrated = registry.migrated {
            if !migrated.accountID.isEmpty, let token = SecretStore.get(account: SecretStore.legacyAccount) {
                try? SecretStore.set(token, account: SecretStore.key(for: migrated.id))
            }
            SecretStore.clear(account: SecretStore.legacyAccount)
            registry.migrationDone()
        }
        for server in registry.servers where !server.accountID.isEmpty {
            if let token = SecretStore.get(account: SecretStore.key(for: server.id)), !token.isEmpty {
                tokens[server.id] = token
            }
        }
    }

    func isSignedIn(_ server: UUID) -> Bool {
        guard let entry = registry.server(server), !entry.accountID.isEmpty else { return false }
        return !(tokens[server] ?? "").isEmpty
    }

    /// A client for one workspace on a signed-in server, or nil while signed out.
    func client(for server: UUID, workspace remote: String = APIClient.mainWorkspace) -> APIClient? {
        guard isSignedIn(server), let entry = registry.server(server), let url = URL(string: entry.url),
              let token = tokens[server] else { return nil }
        return APIClient(baseURL: url, token: token, workspace: remote)
    }

    /// Signs in to the server at `raw`. Accounts are created on the server's admin page,
    /// not here (ADR 0021). Returns the server's id, or nil when it failed; the status says why.
    func signIn(url raw: String, name: String, password: String) async -> UUID? {
        guard let url = ServerAddress.valid(raw) else {
            status.message = Self.invalidAddress
            return nil
        }
        guard password.count >= 8 else {
            status.message = "Das Passwort braucht mindestens 8 Zeichen."
            return nil
        }
        do {
            let session = try await APIClient(baseURL: url, token: "")
                .openSession(name: name.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            guard let accountID = ServerAddress.accountID(session.account.id) else { throw APIError.invalidResponse }
            let server = registry.signedIn(url: url.absoluteString, accountName: session.account.name, accountID: accountID)
            try SecretStore.set(session.token, account: SecretStore.key(for: server))
            tokens[server] = session.token
            dismissExpiredNotice(server)
            status.message = "Angemeldet."
            return server
        } catch {
            status.message = StatusLine.describe(error)
            return nil
        }
    }

    /// Changes the account's password on `server`. Nil on success, else what went wrong, in
    /// words for the form. Other devices signed in to the account have to sign in again. See ADR 0050.
    func changePassword(on server: UUID, current: String, new: String) async -> String? {
        guard let client = client(for: server) else { return "Nicht angemeldet." }
        do {
            try await client.changePassword(current: current, to: new)
            status.message = "Passwort geändert."
            return nil
        } catch APIError.wrongPassword {
            return "Das bisherige Passwort stimmt nicht."
        } catch APIError.unauthorized {
            expire(server, ifStill: client.token)
            return StatusLine.describe(APIError.unauthorized)
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// Ends the session. Linked workspaces keep their notes and their binding; syncing pauses.
    func logout(_ server: UUID) {
        if let client = client(for: server) {
            Task { try? await client.logout() }
        }
        endSession(of: server)
        status.message = "Abgemeldet. Die Notizen bleiben auf diesem Gerät."
    }

    /// The server no longer knows the session, e.g. after 90 days without use (ADR 0016).
    /// Same as logging out, minus telling the server. Bindings stay, so signing in to the
    /// same account again continues where syncing stopped.
    func expire(_ server: UUID, ifStill used: String) {
        // A request that started before a new login must not end the new session.
        guard !used.isEmpty, tokens[server] == used else { return }
        endSession(of: server)
        expired.insert(server)
        persistExpired()
        status.message = "Anmeldung abgelaufen. Die Notizen bleiben auf diesem Gerät."
    }

    func dismissExpiredNotice(_ server: UUID) {
        expired.remove(server)
        persistExpired()
    }

    /// Workspaces on a server, to choose one to sync with or to take over.
    func remoteWorkspaces(on server: UUID) async -> [RemoteWorkspace] {
        await remoteWorkspaceList(on: server)?.workspaces ?? []
    }

    /// The account's workspaces in its order, and whether the server keeps looks. Nil if it failed.
    func remoteWorkspaceList(on server: UUID) async -> RemoteWorkspaceList? {
        guard let client = client(for: server) else { return nil }
        do {
            return try await client.workspaceList()
        } catch APIError.unauthorized {
            expire(server, ifStill: client.token)
            return nil
        } catch {
            status.message = StatusLine.describe(error)
            return nil
        }
    }

    /// The server's release, as `/v1/health` tells it. Nil if it does not say or cannot be reached.
    func version(of server: UUID) async -> String? {
        guard let entry = registry.server(server), let url = URL(string: entry.url) else { return nil }
        return try? await APIClient(baseURL: url, token: "").health().version
    }

    /// Checks the address as it is typed, after a short pause.
    func addressChanged(_ text: String) {
        probeTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = ServerAddress.valid(trimmed) else {
            connection = trimmed.isEmpty ? .unknown : .failed(Self.invalidAddress)
            return
        }
        connection = .checking
        probeTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                let health = try await APIClient(baseURL: url, token: "").health()
                guard !Task.isCancelled else { return }
                connection = .reachable(health.registration)
            } catch {
                guard !Task.isCancelled else { return }
                connection = .failed(StatusLine.describe(error))
            }
        }
    }

    private func endSession(of server: UUID) {
        SecretStore.clear(account: SecretStore.key(for: server))
        tokens[server] = nil
        registry.signedOut(server)
    }

    private func persistExpired() {
        UserDefaults.standard.set(expired.map(\.uuidString), forKey: Self.expiredKey)
    }
}
