import Foundation
import InkhashCore
import KennelKit
import Observation

/// Where the vault of the Kennel stands on this device (ADR 0082, Kennel ADR 0043, 0058).
enum VaultState: Equatable {
    case unknown
    /// The account has no key yet; „Verschlüsselung einrichten“ makes one.
    case none
    /// The account has a vault, this device has not opened it: pairing or the recovery key opens it.
    case needsKey(KennelVaultRecord)
    /// Open here; the key encrypts notes and blobs of encrypted workspaces (ADR 0052).
    case ready(VaultKey)
    case failed(String)
}

/// The vault through KennelKit, the same for every teamCato app: one recovery key, one pairing, no reset (teamCato ADR
/// 0013, 0016). The account key is kept by `KennelVaultKeyStore`; sync gets it as inkhash's `VaultKey` with the epoch of
/// inkhash's `/vault`, so notes and blobs keep their format (ADR 0052).
@MainActor
@Observable
final class VaultSessions {
    private(set) var states: [UUID: VaultState] = [:]
    private let sessions: ServerSessions
    private let status: StatusLine
    /// The app's own keychain; the teamCato group where the app may use it (Kennel ADR 0043).
    let store: KennelVaultKeyStore

    init(sessions: ServerSessions, status: StatusLine, store: KennelVaultKeyStore = VaultSessions.defaultStore) {
        self.sessions = sessions
        self.status = status
        self.store = store
    }

    static let defaultStore = KennelVaultKeyStore(service: SecretStore.service)

    func state(of server: UUID) -> VaultState {
        states[server] ?? .unknown
    }

    /// The key for encrypted workspaces, or nil while the vault is not open on this device.
    func key(for server: UUID) -> VaultKey? {
        if case .ready(let key) = state(of: server) { return key }
        return nil
    }

    /// Whether the vault came over from inkhash and still has no key pair: inkhash's old recovery key opens it.
    func isFromInkhash(_ server: UUID) -> Bool {
        if case .needsKey(let record) = state(of: server) { return record.isFromInkhash }
        return false
    }

    private func vault(_ server: UUID) -> KennelVault? {
        sessions.session(of: server).map { KennelVault(session: $0, store: store) }
    }

    /// Compares this device with Kennel's vault. A key kept by an older inkhash (`vault-<server>`) is taken over once.
    func check(_ server: UUID) async {
        guard let vault = vault(server), let client = sessions.client(for: server) else { return }
        do {
            switch try await vault.state() {
            case .none:
                SecretStore.clear(account: Self.legacyAccount(server))
                states[server] = VaultState.none
            case .locked(let record):
                if let kept = Self.legacyKey(for: server), kept.keyId == record.keyId {
                    let open = try await vault.adopt(KennelAccountKey(keyId: kept.keyId, material: kept.material))
                    try await ready(open, server: server, client: client)
                } else {
                    states[server] = .needsKey(record)
                }
            case .open(let open):
                try await ready(open, server: server, client: client)
            }
        } catch KennelError.unauthorized {
            sessions.expire(server, ifStill: client.token)
        } catch {
            states[server] = .failed(KennelErrorText.describe(error))
        }
    }

    /// inkhash's `/vault` counted resets: a new epoch bound encrypted libraries anew (ADR 0052). Without resets it stays.
    private func ready(_ open: KennelOpenVault, server: UUID, client: APIClient) async throws {
        let epoch = try await client.vault()?.epoch ?? 0
        states[server] = .ready(VaultKey(keyId: open.accountKey.keyId, material: open.accountKey.material, epoch: epoch))
        SecretStore.clear(account: Self.legacyAccount(server))
    }

    // MARK: For the vault windows; each returns nil on success, else what went wrong.

    func create(_ server: UUID, recoveryKey: KennelRecoveryKey) async -> String? {
        await act(server) { _ = try await $0.create(recoveryKey: recoveryKey) }
    }

    func unlock(_ server: UUID, recoveryKey: KennelRecoveryKey) async -> String? {
        await act(server) { _ = try await $0.open(recoveryKey: recoveryKey) }
    }

    func unlock(_ server: UUID, pairingCode: String) async -> String? {
        await act(server) { _ = try await $0.open(pairingCode: pairingCode) }
    }

    /// Forgets the key on this device, also one an older inkhash kept; Kennel and other devices stay as they are.
    func lock(_ server: UUID) async -> String? {
        await act(server) {
            try $0.lock()
            SecretStore.clear(account: Self.legacyAccount(server))
        }
    }

    func offerPairing(_ server: UUID) async -> Result<KennelPairing, KennelProblem> {
        guard let vault = vault(server) else { return .failure(KennelProblem("Nicht mit Kennel verbunden.")) }
        do {
            return .success(try await vault.offerPairing())
        } catch {
            return .failure(KennelProblem(KennelErrorText.describe(error)))
        }
    }

    func withdraw(_ server: UUID, _ pairing: KennelPairing) async {
        try? await vault(server)?.withdrawPairing(pairing)
    }

    private func act(_ server: UUID, _ work: (KennelVault) async throws -> Void) async -> String? {
        guard let vault = vault(server) else { return "Nicht mit Kennel verbunden." }
        do {
            try await work(vault)
        } catch {
            return KennelErrorText.describe(error)
        }
        await check(server)
        return nil
    }

    /// Disconnecting takes the key off this device.
    func forget(_ server: UUID) {
        if let account = sessions.session(of: server)?.account.id { try? store.clear(accountId: account) }
        SecretStore.clear(account: Self.legacyAccount(server))
        states[server] = nil
    }

    // MARK: The key an older inkhash kept (ADR 0052)

    static func legacyAccount(_ server: UUID) -> String {
        "vault-" + server.uuidString.lowercased()
    }

    static func legacyKey(for server: UUID) -> VaultKey? {
        guard let text = SecretStore.get(account: legacyAccount(server)) else { return nil }
        return try? InkhashJSON.decode(VaultKey.self, from: Data(text.utf8))
    }
}
