import Foundation
import InkhashCore
import Observation
import KennelKit

/// What the app knows about the address typed into the server form.
enum ServerConnection: Equatable {
    case unknown
    case checking
    case reachable(RegistrationMode)
    case failed(String)
}

/// What redeeming a join code came to. See ADR 0071.
enum JoinOutcome: Equatable {
    case joined(UUID)
    /// An invite: the form asks for name and password and tries again.
    case needsAccount
    /// The status says why.
    case failed
}

/// Why no device code came, in words for the sheet.
struct DeviceCodeProblem: Error, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
}

/// Sessions with the servers of this device: signing in and out, tokens in the keychain,
/// expired sessions, and checking an address while it is typed. See ADR 0016 and 0020.
@MainActor
@Observable
final class ServerSessions {
    var connection: ServerConnection = .unknown
    /// Servers whose session the server rejected. Shows a notice until signing in or dismissing it.
    private(set) var expired: Set<UUID>
    /// Sessions by server, as the keychain holds them. A server without one is signed out.
    private var sessions: [UUID: KennelSession] = [:]
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    private let registry: WorkspaceRegistry
    private let status: StatusLine

    private static let expiredKey = "inkhash.expiredServers"
    private static let invalidAddress = "Das ist keine Adresse eines Servers, z. B. kennel.local oder http://192.168.1.5:8790."
    private static let shortPassword = "Das Passwort braucht mindestens 8 Zeichen."

    init(registry: WorkspaceRegistry, status: StatusLine) {
        self.registry = registry
        self.status = status
        expired = Set((UserDefaults.standard.stringArray(forKey: Self.expiredKey) ?? []).compactMap(UUID.init(uuidString:)))
        if let migrated = registry.migrated {
            if let token = SecretStore.get(account: SecretStore.legacyAccount),
               let session = Self.session(of: migrated, token: token) {
                try? Self.store(for: migrated.id).save(session)
            }
            SecretStore.clear(account: SecretStore.legacyAccount)
            registry.migrationDone()
        }
        for server in registry.servers where !server.accountID.isEmpty {
            // Before ADR 0073 the entry held only the token; address and account come from `setup.json` then.
            let stored = try? Self.store(for: server.id).load { data in
                Self.session(of: server, token: String(decoding: data, as: UTF8.self))
            }
            if let stored, !stored.token.isEmpty {
                sessions[server.id] = stored
            }
        }
    }

    /// The keychain entry of a server's session.
    static func store(for server: UUID) -> KennelSessionStore {
        KennelSessionStore(service: SecretStore.service, key: SecretStore.key(for: server))
    }

    /// A session from a bare token and what `setup.json` knows about the server. Nil if something is missing.
    private static func session(of server: ServerEntry, token: String) -> KennelSession? {
        guard !token.isEmpty, !server.accountID.isEmpty, let url = URL(string: server.url) else { return nil }
        return KennelSession(address: url, token: token, account: KennelAccount(id: server.accountID, name: server.accountName))
    }

    func isSignedIn(_ server: UUID) -> Bool {
        guard let entry = registry.server(server), !entry.accountID.isEmpty else { return false }
        return !(sessions[server]?.token ?? "").isEmpty
    }

    /// A client for one workspace on a signed-in server, or nil while signed out.
    func client(for server: UUID, workspace remote: String = APIClient.mainWorkspace) -> APIClient? {
        guard isSignedIn(server), let session = sessions[server] else { return nil }
        return APIClient(session: session, workspace: remote)
    }

    /// Signs in to the server at `raw`, an address or a link to it. Accounts are created on the
    /// server's admin page or by an invite, not here (ADR 0021, 0071). Returns the server's id, or
    /// nil when it failed; the status says why.
    func signIn(url raw: String, name: String, password: String) async -> UUID? {
        guard let url = JoinLinks.parse(raw)?.address else {
            status.message = Self.invalidAddress
            return nil
        }
        guard password.count >= 8 else {
            status.message = Self.shortPassword
            return nil
        }
        do {
            let session = try await KennelClient(address: url)
                .signIn(name: name.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            return try keep(session, from: url, message: "Angemeldet.")
        } catch {
            status.message = StatusLine.describe(error)
            return nil
        }
    }

    /// Redeems a join code at the server at `raw`. Without name and password a device code signs in;
    /// an invite answers `needsAccount`. With both, an invite creates the account. See ADR 0071.
    func join(url raw: String, code rawCode: String, name: String?, password: String?) async -> JoinOutcome {
        guard let url = JoinLinks.parse(raw)?.address else {
            status.message = Self.invalidAddress
            return .failed
        }
        guard let code = JoinCode(rawCode) else {
            status.message = "Der Code hat zwölf Zeichen aus Ziffern und Buchstaben, z. B. K7Q4-2MPA-XW9D."
            return .failed
        }
        var account: KennelNewAccount?
        if let name, let password {
            guard password.count >= 8 else {
                status.message = Self.shortPassword
                return .failed
            }
            account = KennelNewAccount(name: name.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        }
        do {
            let session = try await KennelClient(address: url).join(code: code, account: account)
            let message = account == nil ? "Angemeldet." : "Account angelegt und angemeldet."
            return .joined(try keep(session, from: url, message: message))
        } catch KennelJoinError.needsAccount {
            status.message = "Das ist eine Einladung. Wähle Name und Passwort für deinen neuen Account."
            return .needsAccount
        } catch KennelJoinError.nameTaken {
            status.message = "Diesen Namen gibt es schon. Wähle einen anderen."
            return .failed
        } catch KennelError.unauthorized {
            status.message = "Der Code gilt nicht mehr oder stimmt nicht. Lass dir einen neuen geben."
            return .failed
        } catch {
            status.message = StatusLine.describe(error)
            return .failed
        }
    }

    /// Stores a new session of `url` and returns the server's id.
    private func keep(_ session: KennelSession, from url: URL, message: String) throws -> UUID {
        guard let accountID = ServerAddress.accountID(session.account.id) else { throw KennelError.invalidReply }
        let server = registry.signedIn(url: url.absoluteString, accountName: session.account.name, accountID: accountID)
        try Self.store(for: server).save(session)
        sessions[server] = session
        dismissExpiredNotice(server)
        status.message = message
        return server
    }

    /// Changes the account's password on `server`. Nil on success, else what went wrong, in
    /// words for the form. Other devices signed in to the account have to sign in again. See ADR 0050.
    func changePassword(on server: UUID, current: String, new: String) async -> String? {
        guard let client = client(for: server) else { return "Nicht angemeldet." }
        do {
            try await client.kennel.changePassword(current: current, to: new)
            status.message = "Passwort geändert."
            return nil
        } catch KennelPasswordError.wrongPassword {
            return "Das bisherige Passwort stimmt nicht."
        } catch KennelError.unauthorized {
            expire(server, ifStill: client.token)
            return StatusLine.describe(KennelError.unauthorized)
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// A code for another device of the account on `server`, or what went wrong. See ADR 0072.
    func createDeviceCode(on server: UUID) async -> Result<IssuedJoinCode, DeviceCodeProblem> {
        guard let client = client(for: server) else { return .failure(DeviceCodeProblem("Nicht angemeldet.")) }
        do {
            return .success(try await client.kennel.issueJoinCode(.device))
        } catch KennelError.unauthorized {
            expire(server, ifStill: client.token)
            return .failure(DeviceCodeProblem(StatusLine.describe(KennelError.unauthorized)))
        } catch let error as KennelError where error.status == 404 {
            return .failure(DeviceCodeProblem("Dieser Kennel kann noch keine Codes für Geräte erzeugen. Ein Update von Kennel hilft."))
        } catch {
            return .failure(DeviceCodeProblem(StatusLine.describe(error)))
        }
    }

    /// Withdraws a device code. Nil on success, also when it was used or expired already, else what went wrong.
    func revokeJoinCode(_ id: String, on server: UUID) async -> String? {
        guard let client = client(for: server) else { return "Nicht angemeldet." }
        do {
            try await client.kennel.revokeJoinCode(id)
            return nil
        } catch let error as KennelError where error.status == 404 {
            return nil
        } catch KennelError.unauthorized {
            expire(server, ifStill: client.token)
            return StatusLine.describe(KennelError.unauthorized)
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// Ends the session. Linked workspaces keep their notes and their binding; syncing pauses.
    func logout(_ server: UUID) {
        if let client = client(for: server) {
            Task { try? await client.kennel.signOut() }
        }
        endSession(of: server)
        status.message = "Abgemeldet. Die Notizen bleiben auf diesem Gerät."
    }

    /// The server no longer knows the session, e.g. after 90 days without use (ADR 0016).
    /// Same as logging out, minus telling the server. Bindings stay, so signing in to the
    /// same account again continues where syncing stopped.
    func expire(_ server: UUID, ifStill used: String) {
        // A request that started before a new login must not end the new session.
        guard !used.isEmpty, sessions[server]?.token == used else { return }
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
        return try? await KennelClient(address: url).health().version
    }

    static let noInkhash = "Unter dieser Adresse läuft kein Kennel mit inkhash. Ist das Modul in der Verwaltung eingeschaltet?"

    /// Checks the address as it is typed, after a short pause.
    func addressChanged(_ text: String) {
        probeTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = JoinLinks.parse(trimmed)?.address else {
            connection = trimmed.isEmpty ? .unknown : .failed(Self.invalidAddress)
            return
        }
        connection = .checking
        probeTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                let health = try await KennelClient(address: url).health()
                guard !Task.isCancelled else { return }
                // inkhash syncs only with Kennel's module, not with the old inkhashd. See ADR 0067.
                connection = health.inkhash == nil ? .failed(Self.noInkhash) : .reachable(health.registrationMode)
            } catch {
                guard !Task.isCancelled else { return }
                connection = .failed(StatusLine.describe(error))
            }
        }
    }

    private func endSession(of server: UUID) {
        try? Self.store(for: server).clear()
        sessions[server] = nil
        registry.signedOut(server)
    }

    private func persistExpired() {
        UserDefaults.standard.set(expired.map(\.uuidString), forKey: Self.expiredKey)
    }
}
