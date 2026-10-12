import CommonCrypto
import CryptoKit
import Foundation

/// The account's vault as the server keeps it: the account key, wrapped with a key made from the
/// recovery key only the devices know. See ADR 0052, 0054.
public struct VaultRecord: Codable, Equatable, Sendable {
    public struct KDF: Codable, Equatable, Sendable {
        public var name: String
        public var rounds: Int
        /// Base64.
        public var salt: String

        public init(name: String, rounds: Int, salt: String) {
            self.name = name
            self.rounds = rounds
            self.salt = salt
        }
    }

    /// Lowercase UUID of the account key.
    public var keyId: String
    public var kdf: KDF
    /// Base64 of version byte, nonce, ciphertext and tag of the account key.
    public var wrapped: String
    /// How often the account's vault was reset. Missing in what a device sends.
    public var epoch: Int?

    public init(keyId: String, kdf: KDF, wrapped: String, epoch: Int? = nil) {
        self.keyId = keyId
        self.kdf = kdf
        self.wrapped = wrapped
        self.epoch = epoch
    }
}

/// The unwrapped account key, as a device keeps it in its keychain.
public struct VaultKey: Codable, Equatable, Sendable {
    public var keyId: String
    /// 32 bytes.
    public var material: Data
    /// The vault's epoch when this key was opened. A reset counts it up. See ADR 0052.
    public var epoch: Int

    public init(keyId: String, material: Data, epoch: Int) {
        self.keyId = keyId
        self.material = material
        self.epoch = epoch
    }
}

public enum VaultError: Error, Equatable {
    case wrongRecoveryKey
    case unsupported
    case damaged
}

/// Making, opening and rewrapping vaults. Pure functions over CryptoKit and CommonCrypto.
public enum VaultCrypto {
    public static let kdfName = "pbkdf2-sha256"
    public static let rounds = 600_000
    static let format: UInt8 = 1

    /// A new account key, wrapped with `recoveryKey`.
    public static func create(recoveryKey: RecoveryKey, epoch: Int = 0, rounds: Int = rounds) throws -> (VaultKey, VaultRecord) {
        let material = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let key = VaultKey(keyId: UUID().uuidString.lowercased(), material: material, epoch: epoch)
        return (key, try wrap(key, recoveryKey: recoveryKey, rounds: rounds))
    }

    /// The account key in `record`. A wrong recovery key fails authentication, nothing else can.
    public static func open(_ record: VaultRecord, recoveryKey: RecoveryKey) throws -> VaultKey {
        guard record.kdf.name == kdfName, record.kdf.rounds > 0,
              let salt = Data(base64Encoded: record.kdf.salt),
              let wrapped = Data(base64Encoded: record.wrapped),
              wrapped.first == format else { throw VaultError.unsupported }
        let kek = try derive(recoveryKey.canonical, salt: salt, rounds: record.kdf.rounds)
        do {
            let box = try AES.GCM.SealedBox(combined: wrapped.dropFirst())
            let material = try AES.GCM.open(box, using: kek, authenticating: aad(record.keyId))
            guard material.count == 32 else { throw VaultError.damaged }
            return VaultKey(keyId: record.keyId, material: material, epoch: record.epoch ?? 0)
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.wrongRecoveryKey
        }
    }

    /// The same key under a new recovery key.
    public static func wrap(_ key: VaultKey, recoveryKey: RecoveryKey, rounds: Int = rounds) throws -> VaultRecord {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw VaultError.unsupported }
        let kek = try derive(recoveryKey.canonical, salt: salt, rounds: rounds)
        let box = try AES.GCM.seal(key.material, using: kek, authenticating: aad(key.keyId))
        guard let combined = box.combined else { throw VaultError.unsupported }
        return VaultRecord(
            keyId: key.keyId,
            kdf: VaultRecord.KDF(name: kdfName, rounds: rounds, salt: salt.base64EncodedString()),
            wrapped: (Data([format]) + combined).base64EncodedString()
        )
    }

    private static func aad(_ keyId: String) -> Data {
        Data("inkhash-vault-v1:\(keyId)".utf8)
    }

    /// PBKDF2-HMAC-SHA256 over the recovery key in canonical form. A random key would not need
    /// the rounds; they stay so the vault keeps the form the server checks. See ADR 0054.
    static func derive(_ secret: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        let password = Array(secret.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = password.withUnsafeBufferPointer { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                passwordBuffer.withMemoryRebound(to: CChar.self) { chars in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        chars.baseAddress, chars.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        &derived, derived.count
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw VaultError.unsupported }
        return SymmetricKey(data: derived)
    }
}
