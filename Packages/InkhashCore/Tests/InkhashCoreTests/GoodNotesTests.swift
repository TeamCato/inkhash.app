import XCTest
@testable import InkhashCore

final class GoodNotesTests: XCTestCase {
    // MARK: Real file

    /// `docs/fixtures/goodnotes-mixed-pens.goodnotes`: GoodNotes 6 on the Mac, one page with every
    /// pen. CC0, from inkterop (see ADR 0041).
    func testReadsEveryPenOfARealNotebook() throws {
        let notebook = try GoodNotes.read(fixture("goodnotes-mixed-pens.goodnotes"))
        XCTAssertEqual(notebook.pages.count, 1)
        let page = try XCTUnwrap(notebook.pages.first)
        XCTAssertEqual(page.width, 768)
        XCTAssertEqual(page.height, 993, accuracy: 1)
        XCTAssertNil(page.background, "GoodNotes' own paper does not come along")
        let tools = page.strokes.map(\.tool)
        XCTAssertEqual(tools.count, 7)
        XCTAssertEqual(Set(tools), [.ballpoint, .fountain, .marker, .pencil, .highlighter])
        let highlighter = try XCTUnwrap(page.strokes.first { $0.tool == .highlighter })
        XCTAssertEqual(highlighter.color.alpha, 0.5, accuracy: 0.01)
        for stroke in page.strokes {
            XCTAssertGreaterThan(stroke.points.count, 1)
            for point in stroke.points {
                XCTAssertTrue((0...page.width).contains(point.x) && (0...page.height).contains(point.y), "\(stroke.tool) leaves the page")
                XCTAssertGreaterThan(point.width, 0)
            }
        }
    }

    func testRejectsWhatIsNoNotebook() {
        XCTAssertThrowsError(try GoodNotes.read(Data("%PDF-1.7".utf8))) { XCTAssertEqual($0 as? GoodNotesError, .notGoodNotes) }
        let zip = Self.zip(["hello.txt": Array("hi".utf8)])
        XCTAssertThrowsError(try GoodNotes.read(zip)) { XCTAssertEqual($0 as? GoodNotesError, .notGoodNotes) }
    }

    // MARK: Built notebook

    /// Three pages in the index; the event log orders them B before A and deletes C. Canvas is
    /// 1000 units wide, so one unit is 0.768 page points.
    func testOrdersPagesByKeyDropsDeletedPagesAndScales() throws {
        let template = "11111111-1111-1111-1111-111111111111"
        let pageA = "AAAAAAAA-0000-0000-0000-00000000000F"
        let pageB = "BBBBBBBB-0000-0000-0000-000000000001"
        let pageC = "CCCCCCCC-0000-0000-0000-000000000001"
        // Notes layer = page + 1 with carry: ...000F becomes ...0010.
        let notesA = "AAAAAAAA-0000-0000-0000-000000000010"
        let notesB = "BBBBBBBB-0000-0000-0000-000000000002"
        let notesC = "CCCCCCCC-0000-0000-0000-000000000002"

        var events: [UInt8] = []
        events += Self.record(Self.event(30, Self.message(2, Self.string(1, "Heft"))))
        events += Self.record(Self.event(2, Self.string(2, template) + Self.message(8, Self.float(1, 1000) + Self.float(2, 1500))))
        for (page, key) in [(pageA, "b"), (pageB, "a"), (pageC, "c")] {
            events += Self.record(Self.event(54, Self.string(2, page) + Self.message(3, Self.string(1, template)) + Self.message(4, Self.string(1, key))))
        }
        events += Self.record(Self.event(56, Self.string(2, pageC)))

        var index: [UInt8] = []
        for notes in [notesA, notesB, notesC] { index += Self.record(Self.string(1, notes) + Self.string(2, "notes/" + notes)) }

        // Page A: one ballpoint stroke (W = 4, so 2 pt) from (100, 100) to (300, 100), moved by
        // the lasso by (10, 20), colour only blue, which protobuf writes without the zero parts.
        let tpl = Self.flatTPL(width: 4, start: (100, 100), quads: [(200, 100, 300, 100)])
        let stroke = Self.bytes(2, Self.storedLZ4(tpl))
            + Self.message(4, Self.float(3, 1) + Self.float(4, 1))
            + Self.message(6, Self.float(1, 10) + Self.float(2, 20))
        let metadata = Self.string(1, "EEEEEEEE-0000-0000-0000-000000000001") + Self.varint(8, 1) + Self.varint(16, 24)
        let notesContent = Self.record(metadata) + Self.record(Self.message(7, stroke))
            // An erased element: metadata with #3 = 1, then its content, which must not appear.
            + Self.record(metadata + Self.varint(3, 1)) + Self.record(Self.message(7, stroke))
            // A text box does not come along but is counted.
            + Self.record(metadata) + Self.record(Self.message(8, Self.string(6, "{\\rtf1 Hallo}")))

        let data = Self.zip([
            "schema.pb": [0x08, 0x18],
            "index.notes.pb": index,
            "index.events.pb": events,
            "notes/" + notesA: notesContent,
            "notes/" + notesB: [],
            "notes/" + notesC: notesContent,
        ])
        let notebook = try GoodNotes.read(data)
        XCTAssertEqual(notebook.title, "Heft")
        XCTAssertEqual(notebook.pages.count, 2)
        XCTAssertTrue(notebook.pages[0].strokes.isEmpty, "B comes first by its key")
        let page = notebook.pages[1]
        XCTAssertEqual(page.width, 768)
        XCTAssertEqual(page.height, 1152, accuracy: 0.5)
        XCTAssertEqual(page.skipped, 1)
        XCTAssertEqual(page.strokes.count, 1)
        let line = try XCTUnwrap(page.strokes.first)
        XCTAssertEqual(line.tool, .ballpoint)
        XCTAssertEqual(line.color, GoodNotesColor(red: 0, green: 0, blue: 1, alpha: 1))
        let first = try XCTUnwrap(line.points.first)
        let last = try XCTUnwrap(line.points.last)
        XCTAssertEqual(first.x, 110 * 0.768, accuracy: 0.01)
        XCTAssertEqual(first.y, 120 * 0.768, accuracy: 0.01)
        XCTAssertEqual(last.x, 310 * 0.768, accuracy: 0.01)
        // 2 pt on paper is 2 · 132/72 canvas units.
        XCTAssertEqual(first.width, 2 * 132 / 72 * 0.768, accuracy: 0.01)
    }

    func testPageUUIDCarries() {
        XCTAssertEqual(GoodNotes.pageUUID(ofNotes: "AAAAAAAA-0000-0000-0000-000000000010"), "AAAAAAAA-0000-0000-0000-00000000000F")
        XCTAssertEqual(GoodNotes.pageUUID(ofNotes: "aaaaaaaa-0000-0000-0001-000000000000"), "AAAAAAAA-0000-0000-0000-FFFFFFFFFFFF")
    }

    // MARK: Encodings

    func testLZ4BlockCopiesOverlappingMatches() throws {
        // "ab", then a match 2 back of length 6, then an empty last sequence.
        let block: [UInt8] = [0x22, 0x61, 0x62, 0x02, 0x00, 0x00]
        var frame = Array("bv41".utf8) + Self.u32(8) + Self.u32(UInt32(block.count)) + block
        frame += Array("bv4$".utf8)
        XCTAssertEqual(try AppleLZ4.decode(frame), Array("abababab".utf8))
        XCTAssertThrowsError(try AppleLZ4.decode(Array(frame.dropLast(4))))
    }

    func testFlatGeometryFollowsFlags() throws {
        let tpl = Self.flatTPL(width: 3, start: (0, 0), quads: [(1, 0, 2, 0), (3, 0, 4, 0)])
        guard case .flat(let width, let paths) = try GoodNotesGeometry.decode(TPL.decode(tpl)) else {
            return XCTFail("not flat")
        }
        XCTAssertEqual(width, 3)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].quads.count, 2)
        XCTAssertEqual(paths[0].quads[1].end, GoodNotesVector(x: 4, y: 0))
    }

    // MARK: Builders

    private func fixture(_ name: String) throws -> Data {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let file = url.appendingPathComponent("docs/fixtures").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { return try Data(contentsOf: file) }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private static func u32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    private static func u16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    private static func varintBytes(_ value: UInt64) -> [UInt8] {
        var value = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    private static func varint(_ number: Int, _ value: UInt64) -> [UInt8] {
        varintBytes(UInt64(number << 3)) + varintBytes(value)
    }

    private static func bytes(_ number: Int, _ payload: [UInt8]) -> [UInt8] {
        varintBytes(UInt64(number << 3 | 2)) + varintBytes(UInt64(payload.count)) + payload
    }

    private static func message(_ number: Int, _ payload: [UInt8]) -> [UInt8] { bytes(number, payload) }

    private static func string(_ number: Int, _ text: String) -> [UInt8] { bytes(number, Array(text.utf8)) }

    private static func float(_ number: Int, _ value: Float) -> [UInt8] {
        varintBytes(UInt64(number << 3 | 5)) + u32(value.bitPattern)
    }

    private static func record(_ payload: [UInt8]) -> [UInt8] {
        varintBytes(UInt64(payload.count)) + payload
    }

    /// `{#1 entity, #type body}`.
    private static func event(_ type: Int, _ body: [UInt8]) -> [UInt8] {
        string(1, "99999999-9999-9999-9999-999999999999") + message(type, body)
    }

    private static func storedLZ4(_ payload: [UInt8]) -> [UInt8] {
        Array("bv4-".utf8) + u32(UInt32(payload.count)) + payload + Array("bv4$".utf8)
    }

    private static func flatTPL(width: Float, start: (Float, Float), quads: [(Float, Float, Float, Float)]) -> [UInt8] {
        let format = Array(GoodNotesGeometry.flatFormat.utf8) + [0]
        var body = u16(2) + u32(width.bitPattern)
        body += u32(UInt32(quads.count + 1)) + u16(0) + quads.flatMap { _ in u16(1) }
        body += u32(1) + u32(start.0.bitPattern) + u32(start.1.bitPattern)
        body += u32(UInt32(quads.count)) + quads.flatMap { u32($0.0.bitPattern) + u32($0.1.bitPattern) + u32($0.2.bitPattern) + u32($0.3.bitPattern) }
        body += u16(1) + u32(0)
        return Array("tpl".utf8) + [0] + u32(UInt32(8 + format.count + body.count)) + format + body
    }

    /// A ZIP with stored members. The reader does not check CRCs, so they stay zero.
    private static func zip(_ members: [String: [UInt8]]) -> Data {
        var out: [UInt8] = []
        var directory: [UInt8] = []
        for (name, content) in members.sorted(by: { $0.key < $1.key }) {
            let nameBytes = Array(name.utf8)
            let offset = UInt32(out.count)
            let sizes = u32(UInt32(content.count)) + u32(UInt32(content.count))
            out += u32(0x0403_4B50) + u16(20) + u16(0x0800) + u16(0) + u16(0) + u16(0) + u32(0) + sizes
            out += u16(UInt16(nameBytes.count)) + u16(0) + nameBytes + content
            directory += u32(0x0201_4B50) + u16(20) + u16(20) + u16(0x0800) + u16(0) + u16(0) + u16(0) + u32(0) + sizes
            directory += u16(UInt16(nameBytes.count)) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(offset) + nameBytes
        }
        let directoryOffset = UInt32(out.count)
        out += directory
        out += u32(0x0605_4B50) + u16(0) + u16(0) + u16(UInt16(members.count)) + u16(UInt16(members.count))
        out += u32(UInt32(directory.count)) + u32(directoryOffset) + u16(0)
        return Data(out)
    }
}
