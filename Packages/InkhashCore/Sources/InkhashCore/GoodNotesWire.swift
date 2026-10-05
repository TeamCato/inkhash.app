import Foundation

// The three encodings inside a `.goodnotes` file: protobuf records without a schema, Apple's
// framed LZ4, and Troy Hanson's TPL images for stroke geometry. See ADR 0041.

enum GoodNotesWireError: Error, Equatable {
    case damaged
    case unknownFormat(String)
}

/// One protobuf message, decoded without a schema. Groups (wire types 3 and 4) do not occur.
struct ProtoMessage {
    enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes([UInt8])
        case fixed32(UInt32)
    }

    struct Field {
        var number: Int
        var value: Value
    }

    var fields: [Field]

    /// Nil if the bytes are not a well-formed message.
    init?(_ bytes: [UInt8]) {
        var fields: [Field] = []
        var position = 0
        while position < bytes.count {
            guard let key = Self.varint(bytes, &position) else { return nil }
            let number = Int(key >> 3)
            guard number > 0 else { return nil }
            switch key & 7 {
            case 0:
                guard let value = Self.varint(bytes, &position) else { return nil }
                fields.append(Field(number: number, value: .varint(value)))
            case 1:
                guard position + 8 <= bytes.count else { return nil }
                var value: UInt64 = 0
                for index in 0..<8 { value |= UInt64(bytes[position + index]) << (8 * UInt64(index)) }
                position += 8
                fields.append(Field(number: number, value: .fixed64(value)))
            case 2:
                guard let length = Self.varint(bytes, &position), length <= UInt64(bytes.count - position) else { return nil }
                let end = position + Int(length)
                fields.append(Field(number: number, value: .bytes(Array(bytes[position..<end]))))
                position = end
            case 5:
                guard position + 4 <= bytes.count else { return nil }
                var value: UInt32 = 0
                for index in 0..<4 { value |= UInt32(bytes[position + index]) << (8 * UInt32(index)) }
                position += 4
                fields.append(Field(number: number, value: .fixed32(value)))
            default:
                return nil
            }
        }
        self.fields = fields
    }

    static func varint(_ bytes: [UInt8], _ position: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while position < bytes.count, shift < 64 {
            let byte = bytes[position]
            position += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    /// Splits a `<varint length><message>…` stream. A damaged tail is dropped, not fatal.
    static func records(_ bytes: [UInt8]) -> [[UInt8]] {
        var records: [[UInt8]] = []
        var position = 0
        while position < bytes.count {
            guard let length = varint(bytes, &position), length <= UInt64(bytes.count - position) else { break }
            let end = position + Int(length)
            records.append(Array(bytes[position..<end]))
            position = end
        }
        return records
    }

    func first(_ number: Int) -> Value? {
        fields.first { $0.number == number }?.value
    }

    func has(_ number: Int) -> Bool {
        fields.contains { $0.number == number }
    }

    func bytes(_ number: Int) -> [UInt8]? {
        if case .bytes(let value) = first(number) { return value }
        return nil
    }

    func message(_ number: Int) -> ProtoMessage? {
        bytes(number).flatMap(ProtoMessage.init)
    }

    func string(_ number: Int) -> String? {
        bytes(number).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    /// GoodNotes writes UUIDs as 36 ASCII characters, never as 16 raw bytes.
    func uuid(_ number: Int) -> String? {
        guard let text = string(number), text.count == 36, UUID(uuidString: text) != nil else { return nil }
        return text.uppercased()
    }

    func int(_ number: Int) -> UInt64? {
        if case .varint(let value) = first(number) { return value }
        return nil
    }

    /// A float32 field; nil if absent or not finite.
    func float(_ number: Int) -> Double? {
        guard case .fixed32(let bits) = first(number) else { return nil }
        let value = Double(Float(bitPattern: bits))
        return value.isFinite ? value : nil
    }

    /// `{#1 x, #2 y}`; a missing coordinate is zero, as protobuf leaves out zeros.
    var point: GoodNotesVector? {
        guard has(1) || has(2) else { return nil }
        return GoodNotesVector(x: float(1) ?? 0, y: float(2) ?? 0)
    }
}

struct GoodNotesVector: Equatable {
    var x: Double
    var y: Double
}

/// Apple's framed LZ4 (`COMPRESSION_LZ4`): `bv41` blocks, `bv4-` stored blocks, `bv4$` at the end.
/// Blocks may refer back into earlier output, so one buffer serves the whole frame.
enum AppleLZ4 {
    static let outputLimit = 64 * 1024 * 1024

    static func decode(_ bytes: [UInt8]) throws -> [UInt8] {
        var output: [UInt8] = []
        var position = 0
        while true {
            guard position + 4 <= bytes.count else { throw GoodNotesWireError.damaged }
            let magic = bytes[position..<position + 4]
            position += 4
            if magic.elementsEqual([0x62, 0x76, 0x34, 0x24]) { return output }
            if magic.elementsEqual([0x62, 0x76, 0x34, 0x31]) {
                guard position + 8 <= bytes.count else { throw GoodNotesWireError.damaged }
                let size = Int(u32(bytes, position))
                let compressed = Int(u32(bytes, position + 4))
                position += 8
                guard position + compressed <= bytes.count, output.count + size <= outputLimit else { throw GoodNotesWireError.damaged }
                try block(bytes[position..<position + compressed], into: &output, size: size)
                position += compressed
            } else if magic.elementsEqual([0x62, 0x76, 0x34, 0x2D]) {
                guard position + 4 <= bytes.count else { throw GoodNotesWireError.damaged }
                let size = Int(u32(bytes, position))
                position += 4
                guard position + size <= bytes.count, output.count + size <= outputLimit else { throw GoodNotesWireError.damaged }
                output.append(contentsOf: bytes[position..<position + size])
                position += size
            } else {
                throw GoodNotesWireError.damaged
            }
        }
    }

    /// One raw LZ4 block that must produce exactly `size` bytes.
    private static func block(_ source: ArraySlice<UInt8>, into output: inout [UInt8], size: Int) throws {
        let limit = output.count + size
        var position = source.startIndex
        let end = source.endIndex
        func length(_ base: Int) throws -> Int {
            var value = base
            while true {
                guard position < end else { throw GoodNotesWireError.damaged }
                let byte = Int(source[position])
                position += 1
                value += byte
                if byte != 255 { return value }
            }
        }
        while position < end {
            let token = Int(source[position])
            position += 1
            var literals = token >> 4
            if literals == 15 { literals = try length(literals) }
            guard position + literals <= end, output.count + literals <= limit else { throw GoodNotesWireError.damaged }
            output.append(contentsOf: source[position..<position + literals])
            position += literals
            if position == end { break }
            guard position + 2 <= end else { throw GoodNotesWireError.damaged }
            let offset = Int(source[position]) | Int(source[position + 1]) << 8
            position += 2
            var match = token & 15
            if match == 15 { match = try length(match) }
            match += 4
            guard offset > 0, offset <= output.count, output.count + match <= limit else { throw GoodNotesWireError.damaged }
            let from = output.count - offset
            for index in 0..<match { output.append(output[from + index]) }
        }
        guard output.count == limit else { throw GoodNotesWireError.damaged }
    }

    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}

/// A TPL image: `tpl`, a flag byte, the total length, a format string, then the packed values,
/// little-endian without padding. Coordinates are `u` words carrying float32 bits.
enum TPL {
    indirect enum Node {
        case scalar(Character)
        case array([Node])
        case tuple([Node])
    }

    indirect enum Value {
        case int(UInt64)
        case double(Double)
        case list([Value])

        var int: UInt64? {
            if case .int(let value) = self { return value }
            return nil
        }

        var list: [Value] {
            if case .list(let values) = self { return values }
            return []
        }

        var float32: Double {
            if case .int(let bits) = self { return Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits))) }
            return 0
        }
    }

    struct Image {
        var format: String
        var values: [Value]
    }

    private static let sizes: [Character: Int] = ["c": 1, "j": 2, "v": 2, "i": 4, "u": 4, "I": 8, "U": 8, "f": 8]

    static func decode(_ bytes: [UInt8]) throws -> Image {
        guard bytes.count >= 9, bytes.starts(with: [0x74, 0x70, 0x6C]) else { throw GoodNotesWireError.damaged }
        guard bytes[3] & 1 == 0 else { throw GoodNotesWireError.damaged }
        let total = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
        guard total == bytes.count, let nul = bytes[8...].firstIndex(of: 0) else { throw GoodNotesWireError.damaged }
        let format = String(decoding: bytes[8..<nul], as: UTF8.self)
        let nodes = try parse(Array(format))
        var position = nul + 1
        var values: [Value] = []
        for node in nodes { values.append(try read(node, bytes, &position)) }
        guard position == bytes.count else { throw GoodNotesWireError.damaged }
        return Image(format: format, values: values)
    }

    private static func parse(_ characters: [Character]) throws -> [Node] {
        var position = 0
        func level(closing: Bool) throws -> [Node] {
            var nodes: [Node] = []
            while position < characters.count {
                let character = characters[position]
                position += 1
                if character == ")" {
                    guard closing else { throw GoodNotesWireError.damaged }
                    return nodes
                }
                if character == "A" || character == "S" {
                    guard position < characters.count, characters[position] == "(" else { throw GoodNotesWireError.damaged }
                    position += 1
                    let inner = try level(closing: true)
                    guard !inner.isEmpty else { throw GoodNotesWireError.damaged }
                    nodes.append(character == "A" ? .array(inner) : .tuple(inner))
                } else if sizes[character] != nil {
                    nodes.append(.scalar(character))
                } else {
                    throw GoodNotesWireError.damaged
                }
            }
            if closing { throw GoodNotesWireError.damaged }
            return nodes
        }
        return try level(closing: false)
    }

    /// Arrays of one scalar become a flat list; arrays of several nodes a list of tuples.
    private static func read(_ node: Node, _ bytes: [UInt8], _ position: inout Int) throws -> Value {
        switch node {
        case .scalar(let character):
            let size = sizes[character] ?? 0
            guard position + size <= bytes.count else { throw GoodNotesWireError.damaged }
            var raw: UInt64 = 0
            for index in 0..<size { raw |= UInt64(bytes[position + index]) << (8 * UInt64(index)) }
            position += size
            return character == "f" ? .double(Double(bitPattern: raw)) : .int(raw)
        case .tuple(let inner):
            var values: [Value] = []
            for child in inner { values.append(try read(child, bytes, &position)) }
            return .list(values)
        case .array(let inner):
            guard position + 4 <= bytes.count else { throw GoodNotesWireError.damaged }
            let count = Int(bytes[position]) | Int(bytes[position + 1]) << 8 | Int(bytes[position + 2]) << 16 | Int(bytes[position + 3]) << 24
            position += 4
            // Every element takes at least one byte; a larger count is a lie.
            guard count <= bytes.count - position else { throw GoodNotesWireError.damaged }
            var items: [Value] = []
            items.reserveCapacity(count)
            for _ in 0..<count {
                if inner.count == 1 {
                    items.append(try read(inner[0], bytes, &position))
                } else {
                    var parts: [Value] = []
                    for child in inner { parts.append(try read(child, bytes, &position)) }
                    items.append(.list(parts))
                }
            }
            return .list(items)
        }
    }
}

/// The geometry of one GoodNotes stroke in canvas units. Each path starts where the flag array
/// puts the pen down; erasing splits a stroke into several paths.
enum GoodNotesGeometry {
    struct Quad {
        var control: GoodNotesVector
        var end: GoodNotesVector
    }

    /// Ballpoint and highlighter: constant width `W`, quadratic Bézier segments.
    case flat(width: Double, paths: [(start: GoodNotesVector, quads: [Quad])])
    /// Fountain pen, brush and marker: on-curve points with a half-width each. `band` is the
    /// constant-radius variant with elliptical caps that the marker writes.
    case ribbon(paths: [[(point: GoodNotesVector, radius: Double)]], band: Bool)
    /// Pencil: points with a nominal width `W`.
    case pencil(width: Double, paths: [[GoodNotesVector]])

    static let flatFormat = "vuA(v)A(S(uu))A(S(uuuu))vA(f)"
    static let flatFormatShort = "vuA(v)A(S(uu))A(S(uuuu))"
    static let ribbonFormat = "vA(v)A(u)A(u)A(v)A(v)A(u)A(u)A(u)A(u)A(v)"
    static let ribbonFormatWidth = "vuA(v)A(u)A(u)A(v)A(v)A(u)A(u)A(u)A(u)A(v)"
    static let pencilFormat = "vuA(v)A(S(uuuuu))A(S(uuuuuuuuuuu))A(S(uu))A(v)A(S(uu))A(S(uuuu))A(u)"

    /// Nil for an element without points, which is what erased elements leave behind.
    /// Unknown format strings are an error rather than a guess.
    static func decode(_ image: TPL.Image) throws -> GoodNotesGeometry? {
        let v = image.values
        switch image.format {
        case flatFormat, flatFormatShort:
            let flags = v[2].list.compactMap(\.int)
            let starts = v[3].list.map { GoodNotesVector(x: $0.list[0].float32, y: $0.list[1].float32) }
            let quads = v[4].list.map { item -> Quad in
                let q = item.list
                return Quad(control: GoodNotesVector(x: q[0].float32, y: q[1].float32), end: GoodNotesVector(x: q[2].float32, y: q[3].float32))
            }
            if flags.isEmpty, starts.isEmpty, quads.isEmpty { return nil }
            var paths: [(start: GoodNotesVector, quads: [Quad])] = []
            var nextStart = 0
            var nextQuad = 0
            for flag in flags {
                if flag == 0 {
                    guard nextStart < starts.count else { throw GoodNotesWireError.damaged }
                    paths.append((starts[nextStart], []))
                    nextStart += 1
                } else {
                    guard nextQuad < quads.count, !paths.isEmpty else { throw GoodNotesWireError.damaged }
                    paths[paths.count - 1].quads.append(quads[nextQuad])
                    nextQuad += 1
                }
            }
            guard nextStart == starts.count, nextQuad == quads.count else { throw GoodNotesWireError.damaged }
            return .flat(width: v[1].float32, paths: paths)

        case ribbonFormat, ribbonFormatWidth:
            let offset = image.format == ribbonFormatWidth ? 1 : 0
            let flags = v[1 + offset].list.compactMap(\.int)
            let startPool = v[2 + offset].list.map(\.float32)
            let panelPool = v[3 + offset].list.map(\.float32)
            if flags.isEmpty { return nil }
            let startCount = flags.filter { $0 % 2 == 0 }.count
            let panelCount = flags.count - startCount
            let startStride = try stride(startPool.count, startCount)
            let panelStride = try stride(panelPool.count, panelCount)
            guard startCount == 0 || startStride >= 3, panelCount == 0 || panelStride >= 6 else { throw GoodNotesWireError.damaged }
            var paths: [[(point: GoodNotesVector, radius: Double)]] = []
            var nextStart = 0
            var nextPanel = 0
            for flag in flags {
                if flag % 2 == 0 {
                    let t = Array(startPool[nextStart * startStride..<(nextStart + 1) * startStride])
                    nextStart += 1
                    paths.append([(GoodNotesVector(x: t[0], y: t[1]), t[2])])
                } else {
                    guard !paths.isEmpty else { throw GoodNotesWireError.damaged }
                    let t = Array(panelPool[nextPanel * panelStride..<(nextPanel + 1) * panelStride])
                    nextPanel += 1
                    if offset == 1 {
                        // The width-word variant stores a panel as (x1, y1, x2, y2, r1, r2).
                        paths[paths.count - 1].append((GoodNotesVector(x: t[0], y: t[1]), t[4]))
                        paths[paths.count - 1].append((GoodNotesVector(x: t[2], y: t[3]), t[5]))
                    } else {
                        paths[paths.count - 1].append((GoodNotesVector(x: t[0], y: t[1]), t[2]))
                        paths[paths.count - 1].append((GoodNotesVector(x: t[3], y: t[4]), t[5]))
                    }
                }
            }
            return .ribbon(paths: paths, band: flags.contains { $0 == 4 || $0 == 5 })

        case pencilFormat:
            let flags = v[2].list.compactMap(\.int)
            let starts = v[3].list
            let segments = v[4].list
            if flags.isEmpty { return nil }
            var paths: [[GoodNotesVector]] = []
            var nextStart = 0
            var nextSegment = 0
            for flag in flags {
                if flag % 2 == 0 {
                    guard nextStart < starts.count else { throw GoodNotesWireError.damaged }
                    let t = starts[nextStart].list
                    nextStart += 1
                    paths.append([GoodNotesVector(x: t[0].float32, y: t[1].float32)])
                } else {
                    guard nextSegment < segments.count, !paths.isEmpty else { throw GoodNotesWireError.damaged }
                    // (seed, x1, y1, a, b, c, x2, y2, a, b, c)
                    let t = segments[nextSegment].list
                    nextSegment += 1
                    paths[paths.count - 1].append(GoodNotesVector(x: t[1].float32, y: t[2].float32))
                    paths[paths.count - 1].append(GoodNotesVector(x: t[6].float32, y: t[7].float32))
                }
            }
            return .pencil(width: v[1].float32, paths: paths)

        default:
            throw GoodNotesWireError.unknownFormat(image.format)
        }
    }

    private static func stride(_ total: Int, _ count: Int) throws -> Int {
        if count == 0 {
            guard total == 0 else { throw GoodNotesWireError.damaged }
            return 0
        }
        guard total % count == 0 else { throw GoodNotesWireError.damaged }
        return total / count
    }
}
