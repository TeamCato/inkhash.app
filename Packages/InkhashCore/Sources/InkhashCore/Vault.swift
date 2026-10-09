import CommonCrypto
import CryptoKit
import Foundation

/// The account's vault as the server keeps it: the account key, wrapped with a key made from a
/// passphrase only the devices know. See ADR 0052.
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
    case wrongPassphrase
    case weakPassphrase
    case unsupported
    case damaged
}

/// Making, opening and rewrapping vaults. Pure functions over CryptoKit and CommonCrypto.
public enum VaultCrypto {
    public static let kdfName = "pbkdf2-sha256"
    public static let rounds = 600_000
    static let format: UInt8 = 1

    /// A new account key, wrapped with `passphrase`.
    public static func create(passphrase: String, epoch: Int = 0, rounds: Int = rounds) throws -> (VaultKey, VaultRecord) {
        guard Passphrase.problem(passphrase) == nil else { throw VaultError.weakPassphrase }
        let material = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let key = VaultKey(keyId: UUID().uuidString.lowercased(), material: material, epoch: epoch)
        return (key, try wrap(key, passphrase: passphrase, rounds: rounds))
    }

    /// The account key in `record`. A wrong passphrase fails authentication, nothing else can.
    public static func open(_ record: VaultRecord, passphrase: String) throws -> VaultKey {
        guard record.kdf.name == kdfName, record.kdf.rounds > 0,
              let salt = Data(base64Encoded: record.kdf.salt),
              let wrapped = Data(base64Encoded: record.wrapped),
              wrapped.first == format else { throw VaultError.unsupported }
        let kek = try derive(passphrase, salt: salt, rounds: record.kdf.rounds)
        do {
            let box = try AES.GCM.SealedBox(combined: wrapped.dropFirst())
            let material = try AES.GCM.open(box, using: kek, authenticating: aad(record.keyId))
            guard material.count == 32 else { throw VaultError.damaged }
            return VaultKey(keyId: record.keyId, material: material, epoch: record.epoch ?? 0)
        } catch let error as VaultError {
            throw error
        } catch {
            throw VaultError.wrongPassphrase
        }
    }

    /// The same key under a new passphrase.
    public static func wrap(_ key: VaultKey, passphrase: String, rounds: Int = rounds) throws -> VaultRecord {
        guard Passphrase.problem(passphrase) == nil else { throw VaultError.weakPassphrase }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw VaultError.unsupported }
        let kek = try derive(passphrase, salt: salt, rounds: rounds)
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

    /// PBKDF2-HMAC-SHA256 over the passphrase in Unicode NFC, so the same words typed on
    /// different keyboards give the same key.
    static func derive(_ passphrase: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        let password = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
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

/// What makes a passphrase acceptable. Long beats clever: it guards everything on the server.
public enum Passphrase {
    public static let minimum = 12

    /// Why `passphrase` is not good enough, in words for the form, or nil.
    public static func problem(_ passphrase: String) -> String? {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < minimum { return "Die Passphrase braucht mindestens \(minimum) Zeichen." }
        if Set(trimmed).count < 4 { return "Die Passphrase ist zu eintönig." }
        return nil
    }

    /// Why a new passphrase and its repetition cannot be used, or nil.
    public static func problem(_ passphrase: String, repeated: String) -> String? {
        if let problem = problem(passphrase) { return problem }
        return passphrase == repeated ? nil : "Die Wiederholung passt nicht."
    }
}
