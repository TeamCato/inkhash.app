import CryptoKit
import Foundation

public enum PairingError: Error, Equatable {
    /// The scanned code is not an inkhash pairing code.
    case notACode
    /// The package does not open with this code: another code, or damaged.
    case damaged
}

/// One handover of the account key from a device with an open vault to a new one. The code goes
/// through the camera, the sealed key through the server, which cannot open it. See ADR 0054.
public struct Pairing: Equatable, Sendable {
    static let prefix = "inkhash-pair:1:"
    static let info = Data("inkhash-pairing-v1".utf8)
    static let format: UInt8 = 1

    /// Names the package on the server.
    public let id: UUID
    /// 32 random bytes. Only in the code, never on the server.
    public let secret: Data

    init(id: UUID, secret: Data) {
        self.id = id
        self.secret = secret
    }

    public static func make() -> Pairing {
        Pairing(id: UUID(), secret: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    /// Reads a scanned code. Throws `notACode` for anything else.
    public init(code: String) throws {
        let text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(Self.prefix) else { throw PairingError.notACode }
        let parts = text.dropFirst(Self.prefix.count).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
              let secret = Self.base64URLDecode(String(parts[1])), secret.count == 32 else { throw PairingError.notACode }
        self.init(id: id, secret: secret)
    }

    /// Whether a scanned text is meant as a pairing code, before reading it in full.
    public static func isCode(_ text: String) -> Bool {
        text.hasPrefix(prefix)
    }

    /// What the QR code shows.
    public var code: String {
        Self.prefix + id.uuidString.lowercased() + ":" + Self.base64URLEncode(secret)
    }

    /// The account key, sealed for the server to hold. Base64.
    public func seal(_ key: VaultKey) throws -> String {
        let box = try AES.GCM.seal(try InkhashJSON.encode(key), using: symmetricKey, authenticating: aad)
        guard let combined = box.combined else { throw PairingError.damaged }
        return (Data([Self.format]) + combined).base64EncodedString()
    }

    public func open(_ sealed: String) throws -> VaultKey {
        guard let data = Data(base64Encoded: sealed), data.first == Self.format else { throw PairingError.damaged }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst())
            return try InkhashJSON.decode(VaultKey.self, from: try AES.GCM.open(box, using: symmetricKey, authenticating: aad))
        } catch {
            throw PairingError.damaged
        }
    }

    private var symmetricKey: SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret), info: Self.info, outputByteCount: 32)
    }

    private var aad: Data {
        Data("inkhash-pairing-v1:\(id.uuidString.lowercased())".utf8)
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }
}
