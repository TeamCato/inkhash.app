import Foundation
import InkhashCore
import Observation

/// Where the vault of the Kennel stands on this device. inkhash creates no vaults anymore; an old one is opened only
/// to read encrypted workspaces once, so they can be converted (ADR 0077, teamCato ADR 0009 point 10).
enum VaultState: Equatable {
    case unknown
    /// The account has no vault.
    case none
    /// The account has a vault, this device lacks its key: the recovery key opens it.
    case needsKey(VaultRecord)
    /// The key is in the keychain and matches Kennel's vault.
    case ready(VaultKey)
    case failed(String)
}

/// The vault key of this device, for reading encrypted workspaces until they are converted: checked against Kennel,
/// opened with the recovery key, forgotten with the Kennel. See ADR 0052, 0054, 0077.
@MainActor
@Observable
final class VaultSessions {
    private(set) var states: [UUID: VaultState] = [:]
    private let sessions: ServerSessions
    private let status: StatusLine

    init(sessions: ServerSessions, status: StatusLine) {
        self.sessions = sessions
        self.status = status
    }

    func state(of server: UUID) -> VaultState {
        states[server] ?? .unknown
    }

    /// The key to read encrypted workspaces with, or nil while the vault is not open on this device.
    func key(for server: UUID) -> VaultKey? {
        if case .ready(let key) = state(of: server) { return key }
        return nil
    }

    /// Compares the keychain with Kennel's vault.
    func check(_ server: UUID) async {
        guard let client = sessions.client(for: server) else { return }
        do {
            let stored = Self.storedKey(for: server)
            guard let record = try await client.vault() else {
                // Reset on another device, or never made: whatever key is here is no longer the account's.
                if stored != nil { SecretStore.clear(account: Self.keychainAccount(server)) }
                states[server] = VaultState.none
                return
            }
            if var key = stored, key.keyId == record.keyId {
                key.epoch = record.epoch ?? 0
                try? Self.store(key, for: server)
                states[server] = .ready(key)
            } else {
                states[server] = .needsKey(record)
            }
        } catch APIError.unauthorized {
            sessions.expire(server, ifStill: client.token)
        } catch {
            states[server] = .failed(StatusLine.describe(error))
        }
    }

    /// Opens the vault with the recovery key and keeps the account key on this device, until the encrypted
    /// workspaces are converted. Nil on success, else why not, for the sheet.
    func unlock(_ server: UUID, recoveryKey: RecoveryKey) async -> String? {
        if case .unknown = state(of: server) { await check(server) }
        guard case .needsKey(let record) = state(of: server) else {
            return key(for: server) == nil ? "Kennel hat für diesen Account keinen Tresor." : nil
        }
        do {
            let key = try await Task.detached { try VaultCrypto.open(record, recoveryKey: recoveryKey) }.value
            try Self.store(key, for: server)
            states[server] = .ready(key)
            status.message = "Tresor offen. Die verschlüsselten Workspaces werden jetzt umgewandelt."
            return nil
        } catch VaultError.wrongRecoveryKey {
            return "Der Wiederherstellungsschlüssel passt nicht zu diesem Tresor."
        } catch VaultError.unsupported {
            return "Dieser Tresor stammt aus einer neueren Version der App."
        } catch {
            return StatusLine.describe(error)
        }
    }

    /// Disconnecting takes the key off this device.
    func forget(_ server: UUID) {
        SecretStore.clear(account: Self.keychainAccount(server))
        states[server] = nil
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
