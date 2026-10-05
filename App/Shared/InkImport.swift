import CoreGraphics
import Foundation
import PencilKit
#if canImport(InkhashCore)
// The spike tool in tools/PdfInkSpike.swift compiles this file next to PDFInk.swift in one module.
import InkhashCore
#endif
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Turns the paths read from a PDF into PencilKit strokes. See ADR 0024.
enum InkImport {
    struct ImportedPage {
        var data: Data
        var width: Double
        var height: Double
    }

    /// Reads every page, drops repeated template lines, and renders each page as a PKDrawing.
    static func pages(fromPDF data: Data) throws -> [ImportedPage] {
        let pages = PDFInk.withoutRepeated(try PDFInk.pages(from: data))
        return pages.map { page in
            ImportedPage(data: drawing(from: page).dataRepresentation(), width: page.width, height: page.height)
        }
    }

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
    #else
    private static func color(_ c: PDFInkColor) -> NSColor {
        NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
    #endif
}
