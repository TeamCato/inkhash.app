import Compression
import Foundation

public enum ZipError: Error, Equatable {
    case notAZip
    /// ZIP64, encryption or a compression method other than stored and deflate.
    case unsupported
    case damaged
    case tooLarge
}

/// Reads the members of a ZIP archive held in memory. Stored and deflated members only, no ZIP64,
/// no encryption: enough for `.goodnotes` files. See ADR 0041.
public struct ZipArchive: Sendable {
    public struct Entry: Equatable, Sendable {
        public var name: String
        var method: UInt16
        var flags: UInt16
        var compressedSize: Int
        public var size: Int
        var headerOffset: Int
    }

    /// A member that inflates beyond this is refused before a byte is inflated.
    public static let memberLimit = 256 * 1024 * 1024

    public let entries: [String: Entry]
    private let bytes: [UInt8]

    public init(_ data: Data) throws {
        let bytes = [UInt8](data)
        self.bytes = bytes
        guard bytes.count >= 22, bytes.starts(with: [0x50, 0x4B]) else { throw ZipError.notAZip }
        // The end-of-central-directory record sits in the last 22 + 65 535 bytes.
        let floor = max(0, bytes.count - 22 - 0xFFFF)
        var end: Int?
        var index = bytes.count - 22
        while index >= floor {
            if Self.u32(bytes, index) == 0x0605_4B50 {
                end = index
                break
            }
            index -= 1
        }
        guard let end else { throw ZipError.notAZip }
        let count = Int(Self.u16(bytes, end + 10))
        let directorySize = Int(Self.u32(bytes, end + 12))
        let directoryOffset = Int(Self.u32(bytes, end + 16))
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF { throw ZipError.unsupported }
        guard directoryOffset + directorySize <= bytes.count else { throw ZipError.damaged }

        var entries: [String: Entry] = [:]
        var position = directoryOffset
        for _ in 0..<count {
            guard position + 46 <= bytes.count, Self.u32(bytes, position) == 0x0201_4B50 else { throw ZipError.damaged }
            let flags = Self.u16(bytes, position + 8)
            let method = Self.u16(bytes, position + 10)
            let compressed = Self.u32(bytes, position + 20)
            let size = Self.u32(bytes, position + 24)
            let nameLength = Int(Self.u16(bytes, position + 28))
            let extraLength = Int(Self.u16(bytes, position + 30))
            let commentLength = Int(Self.u16(bytes, position + 32))
            let offset = Self.u32(bytes, position + 42)
            if compressed == 0xFFFF_FFFF || size == 0xFFFF_FFFF || offset == 0xFFFF_FFFF { throw ZipError.unsupported }
            let nameStart = position + 46
            guard nameStart + nameLength <= bytes.count else { throw ZipError.damaged }
            let name = String(decoding: bytes[nameStart..<nameStart + nameLength], as: UTF8.self)
            if !name.hasSuffix("/") {
                entries[name] = Entry(
                    name: name, method: method, flags: flags, compressedSize: Int(compressed),
                    size: Int(size), headerOffset: Int(offset)
                )
            }
            position = nameStart + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    public func contains(_ name: String) -> Bool { entries[name] != nil }

    /// The inflated bytes of a member, or nil if there is no such member.
    public func read(_ name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        if entry.flags & 0x1 != 0 { throw ZipError.unsupported }
        guard entry.size <= Self.memberLimit else { throw ZipError.tooLarge }
        let local = entry.headerOffset
        guard local + 30 <= bytes.count, Self.u32(bytes, local) == 0x0403_4B50 else { throw ZipError.damaged }
        let start = local + 30 + Int(Self.u16(bytes, local + 26)) + Int(Self.u16(bytes, local + 28))
        guard start + entry.compressedSize <= bytes.count else { throw ZipError.damaged }
        let raw = Data(bytes[start..<start + entry.compressedSize])
        switch entry.method {
        case 0:
            guard raw.count == entry.size else { throw ZipError.damaged }
            return raw
        case 8:
            return try Self.inflate(raw, size: entry.size)
        default:
            throw ZipError.unsupported
        }
    }

    /// Raw DEFLATE (RFC 1951), which is what `COMPRESSION_ZLIB` decodes.
    static func inflate(_ raw: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        guard !raw.isEmpty else { throw ZipError.damaged }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { target in
            raw.withUnsafeBytes { source in
                compression_decode_buffer(
                    target.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw ZipError.damaged }
        return output
    }

    private static func u16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
