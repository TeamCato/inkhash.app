import CoreGraphics
import Foundation

/// A point of an imported stroke in page coordinates, origin top left, with the stroke's width there.
public struct GoodNotesPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double

    public init(x: Double, y: Double, width: Double) {
        self.x = x
        self.y = y
        self.width = width
    }
}

public struct GoodNotesColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct GoodNotesStroke: Equatable, Sendable {
    public enum Tool: String, Sendable {
        /// Constant width. GoodNotes' ballpoint pen, and shapes.
        case ballpoint
        /// Width changes along the stroke: fountain pen and brush pen.
        case fountain
        /// The opaque marker, a band of constant width.
        case marker
        case pencil
        /// Translucent, drawn under the ink.
        case highlighter
    }

    public var tool: Tool
    public var color: GoodNotesColor
    public var points: [GoodNotesPoint]

    public init(tool: Tool, color: GoodNotesColor, points: [GoodNotesPoint]) {
        self.tool = tool
        self.color = color
        self.points = points
    }
}

/// A photo or sticker on the page: PNG, JPEG or a one-page PDF, placed by its top-left corner.
public struct GoodNotesImage: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// Radians, around the center.
    public var rotation: Double
    public var data: Data
}

/// A page of a PDF that was imported into GoodNotes: slides, a worksheet. GoodNotes' own
/// papers (lines, grids, dots) do not come along. See ADR 0041.
public struct GoodNotesBackground: Equatable, Sendable {
    public var pdf: Data
    /// Zero-based.
    public var pageIndex: Int
}

public struct GoodNotesPage: Equatable, Sendable {
    public var width: Double
    public var height: Double
    /// In drawing order.
    public var strokes: [GoodNotesStroke]
    public var images: [GoodNotesImage]
    public var background: GoodNotesBackground?
    /// Text boxes and other elements that do not come along.
    public var skipped: Int
}

public struct GoodNotesNotebook: Equatable, Sendable {
    /// The notebook's own title; usually equal to the file name.
    public var title: String?
    public var pages: [GoodNotesPage]

    public var skipped: Int { pages.reduce(0) { $0 + $1.skipped } }
}

public enum GoodNotesError: Error, Equatable {
    /// Not a ZIP, or a ZIP without GoodNotes pages.
    case notGoodNotes
    case noPages
}

/// Reads a `.goodnotes` file as written by GoodNotes 5, 6 and 7, which share one container: a ZIP
/// of protobuf record streams, an event log for page order and paper, and one ink layer per page.
/// The format is not documented; this follows the public reverse engineering cited in ADR 0041.
public enum GoodNotes {
    /// GoodNotes canvas units per PDF point.
    static let canvasPerPoint = 132.0 / 72.0
    /// GoodNotes' standard paper, in points, when nothing else says how large a page is.
    static let defaultPageSize = CGSize(width: 455.04, height: 588.45)

    public static func read(_ data: Data, targetWidth: Double = PageGeometry.width) throws -> GoodNotesNotebook {
        let zip: ZipArchive
        do {
            zip = try ZipArchive(data)
        } catch {
            throw GoodNotesError.notGoodNotes
        }
        let notesIndex = try? zip.read("index.notes.pb")
        let hasNotes = zip.entries.keys.contains { $0.hasPrefix("notes/") }
        guard notesIndex != nil || hasNotes else { throw GoodNotesError.notGoodNotes }

        let events = Events((try? zip.read("index.events.pb")).flatMap { $0 }.map { [UInt8]($0) } ?? [])
        var attachments: [String: String] = [:]
        if let index = (try? zip.read("index.attachments.pb")).flatMap({ $0 }) {
            for (uuid, member) in pairs([UInt8](index), prefix: "attachments/") { attachments[uuid] = member }
        }
        for name in zip.entries.keys where name.hasPrefix("attachments/") {
            let uuid = String(name.dropFirst("attachments/".count)).uppercased()
            if attachments[uuid] == nil { attachments[uuid] = name }
        }
        let reader = Reader(zip: zip, attachments: attachments, aliases: events.aliases, targetWidth: targetWidth)

        var entries = notesIndex.flatMap { $0 }.map { pairs([UInt8]($0), prefix: "notes/") } ?? []
        if entries.isEmpty {
            entries = zip.entries.keys.filter { $0.hasPrefix("notes/") }.sorted()
                .map { (String($0.dropFirst("notes/".count)).uppercased(), $0) }
        }
        // Display order is the bytewise order of the page keys; the index is in no order.
        // Pages without a key keep their index position, after the others.
        let ordered = entries.enumerated()
            .filter { !events.isDeleted(notes: $0.element.0) }
            .map { offset, entry -> (key: [UInt8]?, offset: Int, entry: (String, String)) in
                (events.page(notes: entry.0)?.orderKey.map { Array($0.utf8) }, offset, entry)
            }
            .sorted { a, b in
                switch (a.key, b.key) {
                case let (x?, y?): return x.lexicographicallyPrecedes(y) || (x == y && a.offset < b.offset)
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.offset < b.offset
                }
            }
        let pages = ordered.map { reader.page(notes: $0.entry.0, member: $0.entry.1, events: events) }
        guard !pages.isEmpty else { throw GoodNotesError.noPages }
        return GoodNotesNotebook(title: events.title, pages: pages)
    }

    /// `index.notes.pb` and `index.attachments.pb`: `{#1 uuid, #2 member}` per record.
    private static func pairs(_ bytes: [UInt8], prefix: String) -> [(String, String)] {
        ProtoMessage.records(bytes).compactMap { record in
            guard let message = ProtoMessage(record) else { return nil }
            let uuid = message.uuid(1)
            let member = message.string(2) ?? uuid.map { prefix + $0 }
            if let uuid, let member { return (uuid, member) }
            if let member, member.hasPrefix(prefix) { return (String(member.dropFirst(prefix.count)).uppercased(), member) }
            return nil
        }
    }

    /// The notes layer of a page has the page's UUID plus one, as a 128-bit number with carry.
    static func pageUUID(ofNotes notes: String) -> String {
        let digits = Array("0123456789ABCDEF")
        let hex = Array(notes.replacingOccurrences(of: "-", with: "").uppercased())
        guard hex.count == 32, hex.allSatisfy(digits.contains) else { return notes.uppercased() }
        var result = hex
        var index = 31
        while index >= 0 {
            let value = digits.firstIndex(of: result[index])!
            if value > 0 {
                result[index] = digits[value - 1]
                break
            }
            result[index] = "F"
            index -= 1
        }
        let text = String(result)
        let parts = [text.prefix(8), text.dropFirst(8).prefix(4), text.dropFirst(12).prefix(4), text.dropFirst(16).prefix(4), text.dropFirst(20)]
        return parts.map(String.init).joined(separator: "-")
    }
}

// MARK: - Event log

/// `index.events.pb`: one `{#1 entity, #E body}` record per event, the field number E is the type.
private struct Events {
    struct Template {
        var attachment: String?
        var pdfPage = 1
        var canvas: CGSize?
        var name = ""
    }

    struct Page {
        var template: String?
        var orderKey: String?
    }

    var title: String?
    var templates: [String: Template] = [:]
    var pages: [String: Page] = [:]
    var deleted: Set<String> = []
    /// Attachment id → storage id, where a PDF page lives under another name.
    var aliases: [String: String] = [:]

    init(_ bytes: [UInt8]) {
        for record in ProtoMessage.records(bytes) {
            guard let message = ProtoMessage(record),
                  let field = message.fields.first(where: { $0.number != 1 }),
                  case .bytes(let raw) = field.value,
                  let body = ProtoMessage(raw) else { continue }
            switch field.number {
            case 30, 31:
                // Document created, renamed.
                if let name = body.message(2)?.string(1) { title = name }
            case 2:
                // Paper: #2 id, #4 attachment, #5 one-based PDF page, #8 canvas size, #9 name.
                guard let id = body.uuid(2) else { continue }
                var template = Template(attachment: body.uuid(4), pdfPage: Int(body.int(5) ?? 1), name: body.string(9) ?? "")
                if let size = body.message(8), let w = size.float(1), let h = size.float(2), w > 0, h > 0 {
                    template.canvas = CGSize(width: w, height: h)
                }
                templates[id] = template
            case 54, 3:
                // Page created, or bound to another paper; the later event wins.
                guard let id = body.uuid(2) else { continue }
                var page = pages[id] ?? Page()
                if let template = body.message(3)?.uuid(1) { page.template = template }
                if field.number == 54, let key = body.message(4)?.string(1) { page.orderKey = key }
                pages[id] = page
            case 55:
                // Page moved.
                guard let id = body.uuid(2), let key = body.message(3)?.string(1) else { continue }
                pages[id, default: Page()].orderKey = key
            case 56:
                if let id = body.uuid(2) { deleted.insert(id) }
            case 6:
                if let id = body.uuid(1), let storage = body.uuid(2), storage != id { aliases[id] = storage }
            default:
                continue
            }
        }
    }

    func page(notes: String) -> Page? {
        if let page = pages[GoodNotes.pageUUID(ofNotes: notes)] { return page }
        // Files not written by GoodNotes itself sometimes only bump the last digit.
        let prefix = notes.uppercased().prefix(35)
        return pages.first { $0.key.prefix(35) == prefix }?.value
    }

    func isDeleted(notes: String) -> Bool {
        if deleted.contains(GoodNotes.pageUUID(ofNotes: notes)) { return true }
        let prefix = notes.uppercased().prefix(35)
        return deleted.contains { $0.prefix(35) == prefix }
    }
}

// MARK: - Pages

private final class Reader {
    let zip: ZipArchive
    let attachments: [String: String]
    let aliases: [String: String]
    let targetWidth: Double
    private var documents: [String: CGPDFDocument?] = [:]

    init(zip: ZipArchive, attachments: [String: String], aliases: [String: String], targetWidth: Double) {
        self.zip = zip
        self.attachments = attachments
        self.aliases = aliases
        self.targetWidth = targetWidth
    }

    func attachment(_ id: String) -> Data? {
        let member = attachments[id] ?? aliases[id].map { attachments[$0] ?? "attachments/" + $0 } ?? "attachments/" + id
        return (try? zip.read(member)).flatMap { $0 }
    }

    func pdf(_ id: String) -> CGPDFDocument? {
        if let cached = documents[id] { return cached }
        let document = attachment(id).flatMap { data -> CGPDFDocument? in
            guard let provider = CGDataProvider(data: data as CFData) else { return nil }
            return CGPDFDocument(provider)
        }
        documents[id] = document
        return document
    }

    func page(notes: String, member: String, events: Events) -> GoodNotesPage {
        let template = events.page(notes: notes)?.template.flatMap { events.templates[$0] }
        var size = GoodNotes.defaultPageSize
        var background: GoodNotesBackground?
        if let template, let id = template.attachment, let document = pdf(id), document.numberOfPages > 0 {
            let index = min(max(template.pdfPage, 1), document.numberOfPages)
            if let pdfPage = document.page(at: index) {
                let box = pdfPage.getBoxRect(.mediaBox)
                let turned = pdfPage.rotationAngle % 180 != 0
                size = turned ? CGSize(width: box.height, height: box.width) : box.size
                if !Self.isPaper(document, name: template.name), let data = attachment(id) {
                    background = GoodNotesBackground(pdf: data, pageIndex: index - 1)
                }
            }
        } else if let canvas = template?.canvas {
            size = CGSize(width: canvas.width / GoodNotes.canvasPerPoint, height: canvas.height / GoodNotes.canvasPerPoint)
        }
        guard size.width > 0, size.height > 0 else {
            return GoodNotesPage(width: targetWidth, height: PageGeometry.height, strokes: [], images: [], background: nil, skipped: 0)
        }
        let canvasWidth = template?.canvas?.width ?? size.width * GoodNotes.canvasPerPoint
        let scale = targetWidth / canvasWidth
        // The server takes pages up to 10 000 high; a longer strip is cut off at the bottom.
        let height = min(max(size.height * targetWidth / size.width, 1), Limits.pageSide)
        var page = GoodNotesPage(width: targetWidth, height: height, strokes: [], images: [], background: background, skipped: 0)
        if let content = (try? zip.read(member)).flatMap({ $0 }), !content.isEmpty {
            PageParser(reader: self, scale: scale).run([UInt8](content), into: &page)
        }
        return page
    }

    /// GoodNotes' own papers are one-page PDFs made by svg2pdf, named `<UUID>_<kind>_<n>_<n> - <title>`.
    static func isPaper(_ document: CGPDFDocument, name: String) -> Bool {
        if name.range(of: #"^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}_[a-z0-9]+_\d+_\d+ - .+$"#, options: .regularExpression) != nil {
            return true
        }
        guard document.numberOfPages == 1, let info = document.info else { return false }
        var producer: CGPDFStringRef?
        guard CGPDFDictionaryGetString(info, "Producer", &producer), let producer,
              let text = CGPDFStringCopyTextString(producer) as String? else { return false }
        return text == "svg2pdf"
    }
}

/// `notes/<N>`: pairs of a metadata record and a content record, in drawing order. The content
/// record has one field; its number is the kind: 7 stroke, 1 image, 8 and 21 text, 9 shape fill.
private struct PageParser {
    let reader: Reader
    /// Page coordinates per canvas unit.
    let scale: Double

    func run(_ bytes: [UInt8], into page: inout GoodNotesPage) {
        var tombstone = false
        var metadataAttachment: String?
        for record in ProtoMessage.records(bytes) {
            guard let message = ProtoMessage(record) else { continue }
            // Metadata: #1 element UUID, #3 = 1 when erased, #4 attachment, #8/#9/#16 varints.
            if message.uuid(1) != nil, message.fields.contains(where: { [8, 9, 16].contains($0.number) && $0.value.isVarint }) {
                tombstone = message.int(3) == 1
                metadataAttachment = message.uuid(4)
                continue
            }
            defer {
                tombstone = false
                metadataAttachment = nil
            }
            guard !tombstone, message.fields.count == 1, let field = message.fields.first,
                  case .bytes(let raw) = field.value, let body = ProtoMessage(raw) else { continue }
            switch field.number {
            case 7:
                // A damaged file can carry infinite or NaN coordinates; such a stroke is dropped.
                page.strokes.append(contentsOf: strokes(body).filter { stroke in
                    stroke.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.width.isFinite }
                })
            case 1:
                if let image = image(body, attachment: metadataAttachment) { page.images.append(image) }
            case 9:
                // The translucent fill of a closed shape. Its outline comes along as a stroke.
                continue
            default:
                page.skipped += 1
            }
        }
    }

    // MARK: Strokes

    private func strokes(_ body: ProtoMessage) -> [GoodNotesStroke] {
        let color = Self.color(body.message(4))
        let highlighter = body.int(5) == 1
        let marker = body.message(20)?.has(1) == true
        let offset = body.message(6)?.point ?? GoodNotesVector(x: 0, y: 0)
        // #3: absent ballpoint, 1 and 4 fountain or brush, 5 pencil.
        var tool: GoodNotesStroke.Tool = highlighter ? .highlighter : marker ? .marker : body.int(3) == 5 ? .pencil : .ballpoint

        if let shape = body.message(9), let paths = Self.shape(shape) {
            let width = (shape.float(15) ?? 2) / 2 * GoodNotes.canvasPerPoint * scale
            return paths.map { path in
                GoodNotesStroke(tool: tool, color: color, points: path.map { point($0, offset: offset, width: width) })
            }
        }
        guard let frame = body.bytes(2), !frame.isEmpty,
              let decoded = try? AppleLZ4.decode(frame),
              let image = try? TPL.decode(decoded),
              let geometry = try? GoodNotesGeometry.decode(image) else { return [] }

        switch geometry {
        case .flat(let w, let paths):
            // W is the full width in units of half a point.
            let width = w / 2 * GoodNotes.canvasPerPoint * scale
            return paths.map { path in
                var points = [point(path.start, offset: offset, width: width)]
                var from = path.start
                for quad in path.quads {
                    for sample in Self.sample(from: from, control: quad.control, to: quad.end) {
                        points.append(point(sample, offset: offset, width: width))
                    }
                    from = quad.end
                }
                return GoodNotesStroke(tool: tool, color: color, points: points)
            }
        case .ribbon(let paths, let band):
            if !highlighter, band { tool = .marker }
            if tool == .ballpoint { tool = .fountain }
            return paths.map { path in
                GoodNotesStroke(tool: tool, color: color, points: path.map { point($0.point, offset: offset, width: 2 * $0.radius * scale) })
            }
        case .pencil(let w, let paths):
            if !highlighter { tool = .pencil }
            let width = w / 2 * GoodNotes.canvasPerPoint * scale
            return paths.map { path in
                GoodNotesStroke(tool: tool, color: color, points: path.map { point($0, offset: offset, width: width) })
            }
        }
    }

    private func point(_ v: GoodNotesVector, offset: GoodNotesVector, width: Double) -> GoodNotesPoint {
        GoodNotesPoint(x: (v.x + offset.x) * scale, y: (v.y + offset.y) * scale, width: width)
    }

    /// Points along a quadratic Bézier after its start, dense enough for PencilKit to follow.
    static func sample(from start: GoodNotesVector, control: GoodNotesVector, to end: GoodNotesVector) -> [GoodNotesVector] {
        let length = hypot(control.x - start.x, control.y - start.y) + hypot(end.x - control.x, end.y - control.y)
        let steps = length.isFinite ? Int(min(max((length / 6).rounded(.up), 1), 16)) : 1
        return (1...steps).map { step in
            let t = Double(step) / Double(steps)
            let u = 1 - t
            return GoodNotesVector(
                x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
            )
        }
    }

    /// Recognised shapes keep their geometry instead of points: #1 polyline, #2 quadratic curve,
    /// #3 rectangle by center and size, #4 ellipse by center, semi-axes and angle.
    static func shape(_ shape: ProtoMessage) -> [[GoodNotesVector]]? {
        if let ellipse = shape.message(4), let center = ellipse.message(1)?.point, let radii = ellipse.message(2)?.point {
            let angle = ellipse.float(3) ?? 0
            let points = (0...64).map { step -> GoodNotesVector in
                let t = 2 * Double.pi * Double(step % 64) / 64
                let x = radii.x * cos(t)
                let y = radii.y * sin(t)
                return GoodNotesVector(x: center.x + x * cos(angle) - y * sin(angle), y: center.y + x * sin(angle) + y * cos(angle))
            }
            return [points]
        }
        if let rect = shape.message(3), let center = rect.message(1)?.point, let size = rect.message(2)?.point {
            let (w, h) = (size.x / 2, size.y / 2)
            let corners = [(-w, -h), (w, -h), (w, h), (-w, h), (-w, -h)]
            return [corners.map { GoodNotesVector(x: center.x + $0.0, y: center.y + $0.1) }]
        }
        if let curve = shape.message(2) {
            if let start = curve.message(1)?.point, let control = curve.message(2)?.point, let end = curve.message(3)?.point {
                return [[start] + sample(from: start, control: control, to: end)]
            }
            let points = pointList(curve)
            return points.isEmpty ? nil : [points]
        }
        if let line = shape.message(1) {
            let points = pointList(line)
            return points.isEmpty ? nil : [points]
        }
        return nil
    }

    private static func pointList(_ message: ProtoMessage) -> [GoodNotesVector] {
        message.fields.compactMap { field in
            guard case .bytes(let raw) = field.value else { return nil }
            return ProtoMessage(raw)?.point
        }
    }

    /// `{#1 r, #2 g, #3 b, #4 a}` as float32; protobuf leaves out components that are zero.
    static func color(_ message: ProtoMessage?) -> GoodNotesColor {
        guard let message else { return GoodNotesColor(red: 0, green: 0, blue: 0, alpha: 1) }
        let clamp: (Double?) -> Double = { min(max($0 ?? 0, 0), 1) }
        return GoodNotesColor(red: clamp(message.float(1)), green: clamp(message.float(2)), blue: clamp(message.float(3)), alpha: clamp(message.float(4)))
    }

    // MARK: Images

    /// #2 `{#1 top left, #2 size}` in canvas units, #3 crop with an optional rotation, #4 attachment.
    private func image(_ body: ProtoMessage, attachment: String?) -> GoodNotesImage? {
        guard let rect = body.message(2), let origin = rect.message(1)?.point, let size = rect.message(2)?.point,
              size.x > 0, size.y > 0, [origin.x, origin.y, size.x * scale, size.y * scale].allSatisfy(\.isFinite),
              let id = body.uuid(4) ?? attachment,
              let data = reader.attachment(id), Self.isImage(data) else { return nil }
        return GoodNotesImage(
            x: origin.x * scale, y: origin.y * scale, width: size.x * scale, height: size.y * scale,
            rotation: body.message(3)?.float(3) ?? 0, data: data
        )
    }

    static func isImage(_ data: Data) -> Bool {
        let head = [UInt8](data.prefix(5))
        return head.starts(with: [0x89, 0x50, 0x4E, 0x47]) || head.starts(with: [0xFF, 0xD8]) || head.starts(with: Array("%PDF-".utf8))
    }
}

private extension ProtoMessage.Value {
    var isVarint: Bool {
        if case .varint = self { return true }
        return false
    }
}
