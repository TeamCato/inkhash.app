import Foundation
import InkhashCore
import Observation

/// Where the vault of one server stands on this device. See ADR 0052, 0054.
enum VaultState: Equatable {
    case unknown
    /// The account has no vault yet: this device makes a recovery key and creates it.
    case needsSetup
    /// The account has a vault, this device lacks its key: a pairing code or the recovery key opens it.
    case needsKey(VaultRecord)
    /// The key is in the keychain and matches the server's vault.
    case ready(VaultKey)
    /// The server is no Kennel running the module inkhash. Syncing rests. See ADR 0067.
    case noInkhash
    case failed(String)
}

/// Why a pairing code could not be offered, in words for the sheet.
struct PairingFailure: Error {
    var message: String
}

/// The vault keys of this device, one per server: checking them against the server, creating,
/// opening, rewrapping, pairing and resetting vaults. Syncing asks here for the key. See ADR 0052, 0054.
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
            guard health.vault else {
                set(.noInkhash, for: server)
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
                set(.needsKey(record), for: server)
            }
        } catch APIError.unauthorized {
            sessions.expire(server, ifStill: client.token)
        } catch {
            states[server] = .failed(StatusLine.describe(error))
        }
    }

    /// Creates the account's vault with `recoveryKey`. Nil on success, else why not, for the form.
    func create(_ server: UUID, recoveryKey: RecoveryKey) async -> String? {
        guard let client = sessions.client(for: server) else { return "Nicht angemeldet." }
        let rounds = rounds
        do {
            let (key, record) = try await Task.detached { try VaultCrypto.create(recoveryKey: recoveryKey, rounds: rounds) }.value
            let stored = try await client.putVault(record)
            return finish(VaultKey(keyId: key.keyId, material: key.material, epoch: stored.epoch ?? 0), on: server)
        } catch let APIError.vaultExists(existing) {
            set(.needsKey(existing), for: server)
            return "Ein anderes Gerät hat den Tresor eben angelegt. Bitte von dort koppeln oder dessen Wiederherstellungsschlüssel eingeben."
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// Opens the vault with the recovery key and keeps the account key on this device.
    func unlock(_ server: UUID, recoveryKey: RecoveryKey) async -> String? {
        guard case .needsKey(let record) = state(of: server) else { return "Der Tresor ist schon offen." }
        do {
            let key = try await Task.detached { try VaultCrypto.open(record, recoveryKey: recoveryKey) }.value
            return finish(key, on: server)
        } catch VaultError.wrongRecoveryKey {
            return "Der Wiederherstellungsschlüssel passt nicht zu diesem Tresor."
        } catch VaultError.unsupported {
            return "Dieser Tresor stammt aus einer neueren Version der App."
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// Opens the vault with a scanned pairing code: the account key comes sealed from the server. See ADR 0054.
    func unlock(_ server: UUID, pairingCode: String) async -> String? {
        guard case .needsKey(let record) = state(of: server) else { return "Der Tresor ist schon offen." }
        guard let client = sessions.client(for: server) else { return "Nicht angemeldet." }
        do {
            let pairing = try Pairing(code: pairingCode)
            guard let sealed = try await client.takePairing(pairing.id) else {
                return "Der Code ist abgelaufen oder schon benutzt. Bitte auf dem anderen Gerät einen neuen zeigen."
            }
            var key = try pairing.open(sealed)
            guard key.keyId == record.keyId else {
                return "Der Code gehört zu einem anderen Tresor. Ist das andere Gerät am selben Account angemeldet?"
            }
            key.epoch = record.epoch ?? 0
            return finish(key, on: server)
        } catch PairingError.notACode {
            return "Das ist kein Kopplungscode von inkhash."
        } catch PairingError.damaged {
            return "Der Code passt nicht zum Schlüssel auf dem Server. Bitte einen neuen zeigen lassen."
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// Wraps the key with a new recovery key; the old one stops working. Devices that have the key notice nothing.
    func renewRecoveryKey(_ server: UUID, to recoveryKey: RecoveryKey) async -> String? {
        guard let client = sessions.client(for: server), let key = key(for: server) else { return "Der Tresor ist nicht offen." }
        let rounds = rounds
        do {
            let record = try await Task.detached { try VaultCrypto.wrap(key, recoveryKey: recoveryKey, rounds: rounds) }.value
            _ = try await client.putVault(record)
            status.message = "Neuer Wiederherstellungsschlüssel gilt. Der alte nicht mehr."
            return nil
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// Leaves the account key sealed on the server for a new device. The code to show, or why not.
    func offerPairing(_ server: UUID) async -> Result<Pairing, PairingFailure> {
        guard let client = sessions.client(for: server), let key = key(for: server) else {
            return .failure(PairingFailure(message: "Der Tresor ist nicht offen."))
        }
        let pairing = Pairing.make()
        do {
            try await client.offerPairing(pairing.id, sealed: try pairing.seal(key))
            return .success(pairing)
        } catch APIError.notFound {
            // The vault is open, so the route is what is missing: a server from before ADR 0054.
            return .failure(PairingFailure(message: "Der Server kann noch nicht koppeln. Bitte aktualisieren, bis dahin hilft der Wiederherstellungsschlüssel."))
        } catch {
            return .failure(PairingFailure(message: StatusLine.describe(error)))
        }
    }

    /// Takes a shown code back before it is used. Failing quietly is fine: it expires anyway.
    func withdrawPairing(_ server: UUID, id: UUID) async {
        try? await sessions.client(for: server)?.withdrawPairing(id)
    }

    /// For a lost recovery key: with the login password the server drops the account's notes,
    /// then this device makes a new vault. Its notes go up again with the next sync.
    func reset(_ server: UUID, password: String, recoveryKey: RecoveryKey) async -> String? {
        guard let client = sessions.client(for: server) else { return "Nicht angemeldet." }
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
        return await create(server, recoveryKey: recoveryKey)
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
        case .needsSetup, .needsKey, .noInkhash:
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
