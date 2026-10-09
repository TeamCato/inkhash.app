import Foundation

/// Writes a ZIP archive member by member straight to a file, stored without compression.
/// Drawings and photos do not shrink, and `ZipArchive` reads stored members back. No ZIP64:
/// an archive or member past 4 GiB, or more than 65 535 members, is refused. See ADR 0051.
public final class ZipWriter {
    private struct Central {
        var name: Data
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
    }

    private let handle: FileHandle
    private var offset: UInt64 = 0
    private var central: [Central] = []
    private var names: Set<String> = []
    private var finished = false

    /// Creates or replaces the file at `url`.
    public init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
    }

    deinit {
        try? handle.close()
    }

    /// Adds a member. Names use `/` between folders; the same name twice is an error.
    public func add(_ name: String, data: Data) throws {
        precondition(!finished, "ZipWriter is finished")
        guard !name.isEmpty, !name.hasPrefix("/"), names.insert(name).inserted else { throw ZipError.damaged }
        let nameBytes = Data(name.utf8)
        guard nameBytes.count <= 0xFFFF, data.count < 0xFFFF_FFFF, offset < 0xFFFF_FFFF, central.count < 0xFFFF else {
            throw ZipError.tooLarge
        }
        let crc = CRC32.checksum(data)
        var header = Data()
        header.appendLE(UInt32(0x0403_4B50))
        header.appendLE(UInt16(20))
        header.appendLE(Self.utf8Flag)
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0x21))
        header.appendLE(crc)
        header.appendLE(UInt32(data.count))
        header.appendLE(UInt32(data.count))
        header.appendLE(UInt16(nameBytes.count))
        header.appendLE(UInt16(0))
        header.append(nameBytes)
        central.append(Central(name: nameBytes, crc: crc, size: UInt32(data.count), offset: UInt32(offset)))
        try write(header)
        try write(data)
    }

    /// Writes the central directory and closes the file.
    public func finish() throws {
        precondition(!finished, "ZipWriter is finished")
        finished = true
        let start = offset
        for entry in central {
            var record = Data()
            record.appendLE(UInt32(0x0201_4B50))
            record.appendLE(UInt16(20))
            record.appendLE(UInt16(20))
            record.appendLE(Self.utf8Flag)
            record.appendLE(UInt16(0))
            record.appendLE(UInt16(0))
            record.appendLE(UInt16(0x21))
            record.appendLE(entry.crc)
            record.appendLE(entry.size)
            record.appendLE(entry.size)
            record.appendLE(UInt16(entry.name.count))
            record.appendLE(UInt16(0))
            record.appendLE(UInt16(0))
            record.appendLE(UInt16(0))
            record.appendLE(UInt16(0))
            record.appendLE(UInt32(0))
            record.appendLE(entry.offset)
            record.append(entry.name)
            try write(record)
        }
        guard offset < 0xFFFF_FFFF else { throw ZipError.tooLarge }
        var end = Data()
        end.appendLE(UInt32(0x0605_4B50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(central.count))
        end.appendLE(UInt16(central.count))
        end.appendLE(UInt32(offset - start))
        end.appendLE(UInt32(start))
        end.appendLE(UInt16(0))
        try write(end)
        try handle.close()
    }

    /// Bit 11: names are UTF-8.
    private static let utf8Flag = UInt16(0x0800)

    private func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        offset += UInt64(data.count)
    }
}

/// CRC-32 as ZIP uses it (IEEE 802.3, reflected).
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
