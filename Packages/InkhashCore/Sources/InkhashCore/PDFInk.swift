import CoreGraphics
import Foundation

/// A point on an imported page, in page coordinates with the origin top left.
public struct PDFInkPoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: PDFInkPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

public struct PDFInkColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = PDFInkColor(red: 0, green: 0, blue: 0)
}

/// One path from the PDF, flattened to a polyline. A filled path is the outline of a shape; the
/// fountain pen of GoodNotes writes that way. See ADR 0024.
public struct PDFInkStroke: Equatable, Sendable {
    public var points: [PDFInkPoint]
    public var width: Double
    public var color: PDFInkColor
    public var filled: Bool

    public init(points: [PDFInkPoint], width: Double, color: PDFInkColor, filled: Bool) {
        self.points = points
        self.width = width
        self.color = color
        self.filled = filled
    }

    /// Thin ribbons drawn as filled polygons become a stroke along their middle. The polygon runs
    /// down one side and back along the other, so the i-th point pairs with the i-th from the end.
    /// Anything that is not ribbon-shaped stays an outline.
    public func centerline() -> PDFInkStroke {
        guard filled, points.count >= 6 else { return self }
        var ring = points
        if let first = ring.first, let last = ring.last, first == last { ring.removeLast() }
        let half = ring.count / 2
        var middle: [PDFInkPoint] = []
        var widths: [Double] = []
        for index in 0..<half {
            let a = ring[index]
            let b = ring[ring.count - 1 - index]
            middle.append(PDFInkPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
            widths.append(a.distance(to: b))
        }
        let length = zip(middle, middle.dropFirst()).reduce(0.0) { $0 + $1.0.distance(to: $1.1) }
        let meanWidth = widths.reduce(0, +) / Double(max(widths.count, 1))
        guard length > 0, meanWidth < length * 0.5, meanWidth > 0 else { return self }
        return PDFInkStroke(points: middle, width: meanWidth, color: color, filled: false)
    }

    /// Rounded shape of the path, for recognising the same template line on several pages.
    var signature: [Int] {
        points.flatMap { [Int(($0.x * 2).rounded()), Int(($0.y * 2).rounded())] }
    }
}

public struct PDFInkPage: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var strokes: [PDFInkStroke]
    /// Form XObjects the page draws. Their contents are not read yet. See ADR 0024.
    public var skippedForms: Int

    public init(width: Double, height: Double, strokes: [PDFInkStroke], skippedForms: Int = 0) {
        self.width = width
        self.height = height
        self.strokes = strokes
        self.skippedForms = skippedForms
    }
}

public enum PDFInkError: Error, Equatable {
    case notAPDF
    case noPages
}

/// Reads the vector paths of a PDF, page by page, scaled so every page is `targetWidth` wide.
/// Text, images and shadings are ignored. See ADR 0024.
public enum PDFInk {
    public static func pages(from data: Data, targetWidth: Double = PageGeometry.width) throws -> [PDFInkPage] {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else {
            throw PDFInkError.notAPDF
        }
        guard document.numberOfPages > 0 else { throw PDFInkError.noPages }
        var pages: [PDFInkPage] = []
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number) else { continue }
            pages.append(read(page, targetWidth: targetWidth))
        }
        return pages
    }

    /// Drops every stroke whose exact shape appears on more than one page: ruled lines, grids,
    /// margins. Only meaningful with two or more pages.
    public static func withoutRepeated(_ pages: [PDFInkPage]) -> [PDFInkPage] {
        guard pages.count > 1 else { return pages }
        var seenOnPages: [[Int]: Int] = [:]
        for page in pages {
            var onThisPage = Set<[Int]>()
            for stroke in page.strokes { onThisPage.insert(stroke.signature) }
            for signature in onThisPage { seenOnPages[signature, default: 0] += 1 }
        }
        return pages.map { page in
            var copy = page
            copy.strokes = page.strokes.filter { seenOnPages[$0.signature, default: 0] < 2 }
            return copy
        }
    }

    private static func read(_ page: CGPDFPage, targetWidth: Double) -> PDFInkPage {
        let box = page.getBoxRect(.mediaBox)
        let scale = box.width > 0 ? targetWidth / box.width : 1
        // The server takes pages up to 10 000 high; a longer strip is cut off at the bottom.
        let height = min(max(box.height * scale, 1), Limits.pageSide)
        // PDF space has its origin bottom left. Flip, move to the media box, scale to the target.
        let base = CGAffineTransform(translationX: -box.minX, y: -box.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: -scale))
            .concatenating(CGAffineTransform(translationX: 0, y: height))
        let parser = ContentParser(base: base, scale: scale)
        parser.run(page)
        return PDFInkPage(width: targetWidth, height: height, strokes: parser.strokes, skippedForms: parser.skippedForms)
    }
}

/// Walks the content stream with CGPDFScanner. Keeps the graphics state the operators need:
/// transform stack, line width, stroke and fill colour, and the path under construction.
private final class ContentParser {
    struct State {
        var transform: CGAffineTransform
        var lineWidth: Double = 1
        var strokeColor = PDFInkColor.black
        var fillColor = PDFInkColor.black
    }

    private let scale: Double
    var state: State
    private var stack: [State] = []
    private var subpaths: [[PDFInkPoint]] = []
    private var current: [PDFInkPoint] = []
    var currentUser: CGPoint = .zero
    private var subpathStart: CGPoint = .zero
    private(set) var strokes: [PDFInkStroke] = []
    var skippedForms = 0

    init(base: CGAffineTransform, scale: Double) {
        self.scale = scale
        self.state = State(transform: base)
    }

    func run(_ page: CGPDFPage) {
        guard let table = CGPDFOperatorTableCreate() else { return }
        Self.install(table)
        let stream = CGPDFContentStreamCreateWithPage(page)
        let info = Unmanaged.passUnretained(self).toOpaque()
        let scanner = CGPDFScannerCreate(stream, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
    }

    // MARK: Operators

    private static func install(_ table: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(table, "q") { _, info in parser(info)?.push() }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in parser(info)?.pop() }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let v = numbers(scanner, 6) else { return }
            parser(info)?.concat(CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]))
        }
        CGPDFOperatorTableSetCallback(table, "w") { scanner, info in
            guard let v = numbers(scanner, 1) else { return }
            parser(info)?.state.lineWidth = v[0]
        }
        CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
            guard let v = numbers(scanner, 2) else { return }
            parser(info)?.move(to: CGPoint(x: v[0], y: v[1]))
        }
        CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
            guard let v = numbers(scanner, 2) else { return }
            parser(info)?.line(to: CGPoint(x: v[0], y: v[1]))
        }
        CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
            guard let v = numbers(scanner, 6) else { return }
            parser(info)?.curve(CGPoint(x: v[0], y: v[1]), CGPoint(x: v[2], y: v[3]), CGPoint(x: v[4], y: v[5]))
        }
        CGPDFOperatorTableSetCallback(table, "v") { scanner, info in
            guard let v = numbers(scanner, 4), let p = parser(info) else { return }
            p.curve(p.currentUser, CGPoint(x: v[0], y: v[1]), CGPoint(x: v[2], y: v[3]))
        }
        CGPDFOperatorTableSetCallback(table, "y") { scanner, info in
            guard let v = numbers(scanner, 4) else { return }
            let end = CGPoint(x: v[2], y: v[3])
            parser(info)?.curve(CGPoint(x: v[0], y: v[1]), end, end)
        }
        CGPDFOperatorTableSetCallback(table, "h") { _, info in parser(info)?.close() }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let v = numbers(scanner, 4), let p = parser(info) else { return }
            p.move(to: CGPoint(x: v[0], y: v[1]))
            p.line(to: CGPoint(x: v[0] + v[2], y: v[1]))
            p.line(to: CGPoint(x: v[0] + v[2], y: v[1] + v[3]))
            p.line(to: CGPoint(x: v[0], y: v[1] + v[3]))
            p.close()
        }
        // C function pointers cannot capture, so every operator gets its own literal closure.
        CGPDFOperatorTableSetCallback(table, "S") { _, info in parser(info)?.paint(filled: false) }
        CGPDFOperatorTableSetCallback(table, "s") { _, info in
            parser(info)?.close()
            parser(info)?.paint(filled: false)
        }
        CGPDFOperatorTableSetCallback(table, "f") { _, info in parser(info)?.paint(filled: true) }
        CGPDFOperatorTableSetCallback(table, "F") { _, info in parser(info)?.paint(filled: true) }
        CGPDFOperatorTableSetCallback(table, "f*") { _, info in parser(info)?.paint(filled: true) }
        CGPDFOperatorTableSetCallback(table, "B") { _, info in parser(info)?.paint(filled: true) }
        CGPDFOperatorTableSetCallback(table, "B*") { _, info in parser(info)?.paint(filled: true) }
        CGPDFOperatorTableSetCallback(table, "b") { _, info in
            parser(info)?.close()
            parser(info)?.paint(filled: true)
        }
        CGPDFOperatorTableSetCallback(table, "b*") { _, info in
            parser(info)?.close()
            parser(info)?.paint(filled: true)
        }
        CGPDFOperatorTableSetCallback(table, "n") { _, info in parser(info)?.discardPath() }
        CGPDFOperatorTableSetCallback(table, "RG") { scanner, info in
            guard let v = numbers(scanner, 3) else { return }
            parser(info)?.state.strokeColor = PDFInkColor(red: v[0], green: v[1], blue: v[2])
        }
        CGPDFOperatorTableSetCallback(table, "rg") { scanner, info in
            guard let v = numbers(scanner, 3) else { return }
            parser(info)?.state.fillColor = PDFInkColor(red: v[0], green: v[1], blue: v[2])
        }
        CGPDFOperatorTableSetCallback(table, "G") { scanner, info in
            guard let v = numbers(scanner, 1) else { return }
            parser(info)?.state.strokeColor = PDFInkColor(red: v[0], green: v[0], blue: v[0])
        }
        CGPDFOperatorTableSetCallback(table, "g") { scanner, info in
            guard let v = numbers(scanner, 1) else { return }
            parser(info)?.state.fillColor = PDFInkColor(red: v[0], green: v[0], blue: v[0])
        }
        CGPDFOperatorTableSetCallback(table, "K") { scanner, info in
            guard let v = numbers(scanner, 4) else { return }
            parser(info)?.state.strokeColor = cmyk(v)
        }
        CGPDFOperatorTableSetCallback(table, "k") { scanner, info in
            guard let v = numbers(scanner, 4) else { return }
            parser(info)?.state.fillColor = cmyk(v)
        }
        // Colour in a named colour space: the operand count tells gray, RGB or CMYK apart.
        CGPDFOperatorTableSetCallback(table, "SC") { scanner, info in
            if let color = popColor(scanner) { parser(info)?.state.strokeColor = color }
        }
        CGPDFOperatorTableSetCallback(table, "SCN") { scanner, info in
            if let color = popColor(scanner) { parser(info)?.state.strokeColor = color }
        }
        CGPDFOperatorTableSetCallback(table, "sc") { scanner, info in
            if let color = popColor(scanner) { parser(info)?.state.fillColor = color }
        }
        CGPDFOperatorTableSetCallback(table, "scn") { scanner, info in
            if let color = popColor(scanner) { parser(info)?.state.fillColor = color }
        }
        CGPDFOperatorTableSetCallback(table, "Do") { _, info in parser(info)?.skippedForms += 1 }
    }

    // MARK: Graphics state

    func push() { stack.append(state) }

    func pop() {
        if let last = stack.popLast() { state = last }
    }

    func concat(_ matrix: CGAffineTransform) {
        state.transform = matrix.concatenating(state.transform)
    }

    private func map(_ point: CGPoint) -> PDFInkPoint {
        let mapped = point.applying(state.transform)
        return PDFInkPoint(x: mapped.x, y: mapped.y)
    }

    // MARK: Path construction

    func move(to point: CGPoint) {
        flushSubpath()
        current = [map(point)]
        currentUser = point
        subpathStart = point
    }

    func line(to point: CGPoint) {
        if current.isEmpty { current = [map(currentUser)] }
        current.append(map(point))
        currentUser = point
    }

    func curve(_ c1: CGPoint, _ c2: CGPoint, _ end: CGPoint) {
        if current.isEmpty { current = [map(currentUser)] }
        let start = currentUser
        let rough = start.distance(to: c1) + c1.distance(to: c2) + c2.distance(to: end)
        let segments = min(max(Int((rough * scale / 3).rounded(.up)), 2), 32)
        for step in 1...segments {
            let t = Double(step) / Double(segments)
            let u = 1 - t
            let x = u * u * u * start.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x
            let y = u * u * u * start.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y
            current.append(map(CGPoint(x: x, y: y)))
        }
        currentUser = end
    }

    func close() {
        guard !current.isEmpty else { return }
        if let first = current.first, current.last != first { current.append(first) }
        currentUser = subpathStart
        flushSubpath()
    }

    private func flushSubpath() {
        if current.count >= 2 { subpaths.append(current) }
        current = []
    }

    func discardPath() {
        current = []
        subpaths = []
    }

    func paint(filled: Bool) {
        flushSubpath()
        let color = filled ? state.fillColor : state.strokeColor
        let width = max(state.lineWidth * scale * lineScale(), 0.5)
        for points in subpaths {
            strokes.append(PDFInkStroke(points: points, width: width, color: color, filled: filled))
        }
        subpaths = []
    }

    /// Uniform scale the current transform applies on top of the page scale.
    private func lineScale() -> Double {
        let t = state.transform
        let factor = ((abs(t.a * t.d - t.b * t.c)).squareRoot()) / scale
        return factor.isFinite && factor > 0 ? factor : 1
    }
}

// Free functions: the operator callbacks are C function pointers and may not capture anything,
// not even the class they live in.

private func parser(_ info: UnsafeMutableRawPointer?) -> ContentParser? {
    guard let info else { return nil }
    return Unmanaged<ContentParser>.fromOpaque(info).takeUnretainedValue()
}

/// Pops `count` operands. The scanner hands them out last first, so the result is reversed.
private func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [Double]? {
    var values: [Double] = []
    for _ in 0..<count {
        var value: CGPDFReal = 0
        guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
        values.append(Double(value))
    }
    return values.reversed()
}

/// Pops every numeric operand of sc/scn. A pattern name on the stack stays unread and yields nil.
private func popColor(_ scanner: CGPDFScannerRef) -> PDFInkColor? {
    var values: [Double] = []
    var value: CGPDFReal = 0
    while CGPDFScannerPopNumber(scanner, &value) {
        values.append(Double(value))
    }
    values.reverse()
    switch values.count {
    case 1: return PDFInkColor(red: values[0], green: values[0], blue: values[0])
    case 3: return PDFInkColor(red: values[0], green: values[1], blue: values[2])
    case 4: return cmyk(values)
    default: return nil
    }
}

private func cmyk(_ v: [Double]) -> PDFInkColor {
    PDFInkColor(red: (1 - v[0]) * (1 - v[3]), green: (1 - v[1]) * (1 - v[3]), blue: (1 - v[2]) * (1 - v[3]))
}

private extension CGPoint {
    func distance(to other: CGPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}
