import Foundation
import InkhashCore
import Observation

/// Where the vault of one server stands on this device. See ADR 0052.
enum VaultState: Equatable {
    case unknown
    /// The account has no vault yet: this device asks for a passphrase and creates it.
    case needsSetup
    /// The account has a vault, this device lacks its key.
    case needsPassphrase(VaultRecord)
    /// The key is in the keychain and matches the server's vault.
    case ready(VaultKey)
    /// The server keeps no vaults. Syncing waits for an update.
    case serverTooOld
    case failed(String)
}

/// The vault keys of this device, one per server: checking them against the server, creating,
/// opening, rewrapping and resetting vaults. Syncing asks here for the key. See ADR 0052.
@MainActor
@Observable
final class VaultSessions {
    private(set) var states: [UUID: VaultState] = [:]
    /// The server whose vault needs the person now. The app shows the vault sheet for it.
    var prompt: UUID?
    /// Servers whose prompt was put off for this run of the app.
    @ObservationIgnored private var postponed: Set<UUID> = []
    private let sessions: ServerSessions
    private let status: StatusLine
    private let rounds: Int

    init(sessions: ServerSessions, status: StatusLine, rounds: Int = VaultCrypto.rounds) {
        self.sessions = sessions
        self.status = status
        self.rounds = rounds
    }

    func state(of server: UUID) -> VaultState {
        states[server] ?? .unknown
    }

    /// The key to sync with, or nil while the vault is not open on this device.
    func key(for server: UUID) -> VaultKey? {
        if case .ready(let key) = state(of: server) { return key }
        return nil
    }

    /// Compares the keychain with the server's vault. Asks the person if something is missing.
    func check(_ server: UUID) async {
        guard let client = sessions.client(for: server) else { return }
        do {
            let health = try await client.health()
            guard health.vault == true else {
                set(.serverTooOld, for: server)
                return
            }
            let stored = Self.storedKey(for: server)
            guard let record = try await client.vault() else {
                // Reset on another device, or never made: whatever key is here is no longer the account's.
                if stored != nil { SecretStore.clear(account: Self.keychainAccount(server)) }
                set(.needsSetup, for: server)
                return
            }
            if var key = stored, key.keyId == record.keyId {
                key.epoch = record.epoch ?? 0
                try? Self.store(key, for: server)
                set(.ready(key), for: server)
            } else {
                set(.needsPassphrase(record), for: server)
            }
        } catch APIError.unauthorized {
            sessions.expire(server, ifStill: client.token)
        } catch {
            states[server] = .failed(StatusLine.describe(error))
        }
    }

    /// Creates the account's vault with `passphrase`. Nil on success, else why not, for the form.
    func create(_ server: UUID, passphrase: String) async -> String? {
        guard let client = sessions.client(for: server) else { return "Nicht angemeldet." }
        if let problem = Passphrase.problem(passphrase) { return problem }
        let rounds = rounds
        do {
            let (key, record) = try await Task.detached { try VaultCrypto.create(passphrase: passphrase, rounds: rounds) }.value
            let stored = try await client.putVault(record)
            return finish(VaultKey(keyId: key.keyId, material: key.material, epoch: stored.epoch ?? 0), on: server)
        } catch let APIError.vaultExists(existing) {
            set(.needsPassphrase(existing), for: server)
            return "Ein anderes Gerät hat den Tresor eben angelegt. Bitte dessen Passphrase eingeben."
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// Opens the vault with `passphrase` and keeps the key on this device.
    func unlock(_ server: UUID, passphrase: String) async -> String? {
        guard case .needsPassphrase(let record) = state(of: server) else { return "Der Tresor ist schon offen." }
        do {
            let key = try await Task.detached { try VaultCrypto.open(record, passphrase: passphrase) }.value
            return finish(key, on: server)
        } catch VaultError.wrongPassphrase {
            return "Die Passphrase stimmt nicht."
        } catch VaultError.unsupported {
            return "Dieser Tresor stammt aus einer neueren Version der App."
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// Wraps the key with a new passphrase. Devices that have the key notice nothing.
    func changePassphrase(_ server: UUID, to passphrase: String) async -> String? {
        guard let client = sessions.client(for: server), let key = key(for: server) else { return "Der Tresor ist nicht offen." }
        if let problem = Passphrase.problem(passphrase) { return problem }
        let rounds = rounds
        do {
            let record = try await Task.detached { try VaultCrypto.wrap(key, passphrase: passphrase, rounds: rounds) }.value
            _ = try await client.putVault(record)
            status.message = "Passphrase geändert."
            return nil
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// For a forgotten passphrase: with the login password the server drops the account's notes,
    /// then this device makes a new vault. Its notes go up again with the next sync.
    func reset(_ server: UUID, password: String, passphrase: String) async -> String? {
        guard let client = sessions.client(for: server) else { return "Nicht angemeldet." }
        if let problem = Passphrase.problem(passphrase) { return problem }
        do {
            try await client.resetVault(password: password)
        } catch APIError.wrongPassword {
            return "Das Login-Passwort stimmt nicht."
        } catch APIError.notFound {
            // No vault to reset; creating one is all that is left.
        } catch {
            return StatusLine.describe(error)
        }
        SecretStore.clear(account: Self.keychainAccount(server))
        set(.needsSetup, for: server)
        return await create(server, passphrase: passphrase)
    }

    /// Puts the prompt off until the next start of the app.
    func postpone(_ server: UUID) {
        postponed.insert(server)
        if prompt == server { prompt = nil }
    }

    /// Signing out or removing a server takes the key off this device.
    func forget(_ server: UUID) {
        SecretStore.clear(account: Self.keychainAccount(server))
        states[server] = nil
        postponed.remove(server)
        if prompt == server { prompt = nil }
    }

    private func finish(_ key: VaultKey, on server: UUID) -> String? {
        do {
            try Self.store(key, for: server)
        } catch {
            return StatusLine.describe(error)
        }
        set(.ready(key), for: server)
        status.message = "Tresor offen. Die Notizen gehen verschlüsselt zum Server."
        return nil
    }

    private func set(_ state: VaultState, for server: UUID) {
        states[server] = state
        switch state {
        case .needsSetup, .needsPassphrase, .serverTooOld:
            if prompt == nil, !postponed.contains(server) { prompt = server }
        case .ready:
            if prompt == server { prompt = nil }
        case .unknown, .failed:
            break
        }
    }

    // MARK: Keychain

    static func keychainAccount(_ server: UUID) -> String {
        "vault-" + server.uuidString.lowercased()
    }

    static func storedKey(for server: UUID) -> VaultKey? {
        guard let text = SecretStore.get(account: keychainAccount(server)) else { return nil }
        return try? InkhashJSON.decode(VaultKey.self, from: Data(text.utf8))
    }

    static func store(_ key: VaultKey, for server: UUID) throws {
        try SecretStore.set(String(decoding: try InkhashJSON.encode(key), as: UTF8.self), account: keychainAccount(server))
    }
}
