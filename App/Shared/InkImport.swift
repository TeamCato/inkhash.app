import CoreGraphics
import Foundation
import ImageIO
import PencilKit
import UniformTypeIdentifiers
#if canImport(InkhashCore)
// The spike tool in tools/PdfInkSpike.swift compiles this file next to PDFInk.swift in one module.
import InkhashCore
#endif
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Turns the paths read from a PDF, or the strokes of a GoodNotes notebook, into PencilKit
/// strokes. See ADR 0024 and 0041.
enum InkImport {
    struct ImportedPage {
        var data: Data
        var width: Double
        var height: Double
        /// Photos and imported PDF pages as JPEG, each with its element. The element gets its
        /// blob when the JPEG is stored.
        var images: [(element: PageElement, jpeg: Data)] = []
    }

    struct ImportedNotebook {
        var title: String?
        var pages: [ImportedPage]
        /// Text boxes and other elements that did not come along.
        var skipped: Int
    }

    /// Reads every page, drops repeated template lines, and renders each page as a PKDrawing.
    static func pages(fromPDF data: Data) throws -> [ImportedPage] {
        let pages = PDFInk.withoutRepeated(try PDFInk.pages(from: data))
        return pages.map { page in
            ImportedPage(data: drawing(from: page).dataRepresentation(), width: page.width, height: page.height)
        }
    }

    static func notebook(fromGoodNotes data: Data) throws -> ImportedNotebook {
        let notebook = try GoodNotes.read(data)
        let pages = notebook.pages.map { page in
            var imported = ImportedPage(data: drawing(from: page).dataRepresentation(), width: page.width, height: page.height)
            var z = 0
            // An imported PDF page lies under everything else, like the paper it was in GoodNotes.
            if let background = page.background,
               let jpeg = jpeg(fromPDF: background.pdf, pageIndex: background.pageIndex, size: CGSize(width: page.width, height: page.height)) {
                let element = PageElement(kind: .image, x: page.width / 2, y: page.height / 2, width: page.width, height: page.height, z: z)
                imported.images.append((element, jpeg))
                z += 1
            }
            for image in page.images {
                let size = CGSize(width: image.width, height: image.height)
                guard let jpeg = jpeg(fromImage: image.data, size: size) else { continue }
                let element = PageElement(
                    kind: .image, x: image.x + image.width / 2, y: image.y + image.height / 2,
                    width: image.width, height: image.height, rotation: image.rotation, z: z
                )
                imported.images.append((element, jpeg))
                z += 1
            }
            return imported
        }
        return ImportedNotebook(title: notebook.title, pages: pages, skipped: notebook.skipped)
    }

    static func drawing(from page: GoodNotesPage) -> PKDrawing {
        PKDrawing(strokes: page.strokes.compactMap(pkStroke))
    }

    /// Point sizes were measured on macOS 26 with strokes drawn across and along: `.pen` and
    /// `.monoline` draw 2·size − 4 wide, `.pencil` about 1.6·size, and `.marker` is a chisel
    /// that draws 1.4·size wide when it runs across its azimuth. Colors were compared with
    /// GoodNotes' own PDF export of the same notebook.
    private static func pkStroke(_ stroke: GoodNotesStroke) -> PKStroke? {
        guard let first = stroke.points.first else { return nil }
        // A dot is one point; PencilKit needs two to draw anything.
        let points = stroke.points.count == 1 ? [first, GoodNotesPoint(x: first.x + 0.3, y: first.y, width: first.width)] : stroke.points
        let type: PKInk.InkType
        let side: (Double) -> Double
        var opacity = 1.0
        switch stroke.tool {
        case .ballpoint, .marker:
            // GoodNotes' marker is opaque, a band of constant width.
            type = .monoline
            side = { max(($0 + 4) / 2, 2.2) }
        case .fountain:
            type = .pen
            side = { max(($0 + 4) / 2, 2.2) }
        case .pencil:
            // GoodNotes draws its pencil as a faint grain.
            type = .pencil
            side = { max($0 / 1.6, 1) }
            opacity = 0.35
        case .highlighter:
            type = .marker
            side = { max($0 / 1.4, 1) }
        }
        let chisel = type == .marker
        let controlPoints = points.enumerated().map { index, point in
            let size = side(point.width)
            var azimuth = 0.0
            if chisel {
                let a = points[max(index - 1, 0)]
                let b = points[min(index + 1, points.count - 1)]
                azimuth = atan2(b.y - a.y, b.x - a.x) + .pi / 2
            }
            return PKStrokePoint(
                location: CGPoint(x: point.x, y: point.y),
                timeOffset: Double(index) * 0.005,
                size: CGSize(width: size, height: size),
                opacity: opacity,
                force: 1,
                azimuth: azimuth,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        return PKStroke(ink: PKInk(type, color: color(stroke.color)), path: path)
    }

    // MARK: Images

    /// Long side of an imported image, like photos placed by hand (ADR 0028).
    static let maxPixels: CGFloat = 2000

    /// One page of a PDF, rendered on white to fill `size`.
    static func jpeg(fromPDF data: Data, pageIndex: Int, size: CGSize) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let page = document.page(at: pageIndex + 1) else { return nil }
        return render(size: size) { context, rect in
            context.concatenate(fill(rect, with: page))
            context.drawPDFPage(page)
        }
    }

    /// Maps the media box onto `rect`, turned by the page's `/Rotate`. PDF space and a bitmap
    /// context are both y up. `getDrawingTransform` would only ever scale down.
    static func fill(_ rect: CGRect, with page: CGPDFPage) -> CGAffineTransform {
        let box = page.getBoxRect(.mediaBox)
        let angle = ((page.rotationAngle % 360) + 360) % 360
        let turned = angle % 180 != 0
        let width = turned ? box.height : box.width
        let height = turned ? box.width : box.height
        guard width > 0, height > 0 else { return .identity }
        // Applied last to first: move the box to the origin, turn it clockwise, scale it into rect.
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / width, y: rect.height / height)
        switch angle {
        case 90: transform = transform.translatedBy(x: 0, y: height).rotated(by: -.pi / 2)
        case 180: transform = transform.translatedBy(x: width, y: height).rotated(by: .pi)
        case 270: transform = transform.translatedBy(x: width, y: 0).rotated(by: .pi / 2)
        default: break
        }
        return transform.translatedBy(x: -box.minX, y: -box.minY)
    }

    /// A PNG, JPEG or one-page PDF sticker, on white, at the aspect of `size`.
    static func jpeg(fromImage data: Data, size: CGSize) -> Data? {
        if data.starts(with: Array("%PDF-".utf8)) { return jpeg(fromPDF: data, pageIndex: 0, size: size) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return render(size: size) { context, rect in context.draw(image, in: rect) }
    }

    private static func render(size: CGSize, draw: (CGContext, CGRect) -> Void) -> Data? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(2, maxPixels / max(size.width, size.height))
        let width = max(Int(size.width * scale), 1)
        let height = max(Int(size.height * scale), 1)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        // JPEG has no transparency; a sticker's clear parts become paper white.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high
        draw(context, rect)
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // MARK: PDF

    static func drawing(from page: PDFInkPage) -> PKDrawing {
        var strokes: [PKStroke] = []
        for raw in page.strokes {
            let stroke = raw.centerline()
            guard stroke.points.count >= 2 else { continue }
            strokes.append(pkStroke(stroke))
        }
        return PKDrawing(strokes: strokes)
    }

    private static func pkStroke(_ stroke: PDFInkStroke) -> PKStroke {
        // PencilKit's pen draws about 2·size − 4 points wide (measured on macOS 26), so the point
        // size is derived from the width the PDF asked for. Outlines of filled shapes that were not
        // ribbon-shaped stay thin, so a blob reads as a blob.
        let side = stroke.filled ? 1 : max((stroke.width + 4) / 2, 1)
        let size = CGSize(width: side, height: side)
        let points = stroke.points.enumerated().map { index, point in
            PKStrokePoint(
                location: CGPoint(x: point.x, y: point.y),
                timeOffset: Double(index) * 0.005,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: color(stroke.color)), path: path)
    }

    #if os(iOS)
    private static func color(_ c: PDFInkColor) -> UIColor {
        UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    private static func color(_ c: GoodNotesColor) -> UIColor {
        UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
    #else
    private static func color(_ c: PDFInkColor) -> NSColor {
        NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    private static func color(_ c: GoodNotesColor) -> NSColor {
        NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
    #endif
}

extension UTType {
    /// What GoodNotes 5, 6 and 7 name their notebooks; declared as imported in Info.plist.
    static let goodnotes = UTType(importedAs: "com.goodnotesapp.goodnotes.v5", conformingTo: .zip)
}
