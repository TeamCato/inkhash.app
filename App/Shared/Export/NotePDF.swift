import CoreGraphics
import Foundation
import InkhashCore

/// A handwritten note as a PDF: one PDF page per page, paper and elements as vectors, the ink as
/// bitmaps in bands so a tall page never needs one huge image. See ADR 0051.
@MainActor
enum NotePDF {
    /// Ink resolution in pixels per page point.
    static let inkScale: CGFloat = 2
    /// Height of one ink band in page points.
    static let band: CGFloat = 1024

    static func data(for note: Note, load: (String) -> Data?) -> Data? {
        guard note.kind == .ink, let pages = note.pages, let first = pages.first else { return nil }
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return nil }
        var box = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        let info = [kCGPDFContextTitle as String: note.displayTitle, kCGPDFContextCreator as String: "inkhash"] as CFDictionary
        guard let context = CGContext(consumer: consumer, mediaBox: &box, info) else { return nil }
        for page in pages {
            draw(page, paper: note.shownPaper, in: context, load: load)
        }
        context.closePDF()
        return output as Data
    }

    private static func draw(_ page: InkPage, paper: Paper, in context: CGContext, load: (String) -> Data?) {
        var media = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let pageInfo = [kCGPDFContextMediaBox as String: Data(bytes: &media, count: MemoryLayout<CGRect>.size)] as CFDictionary
        context.beginPDFPage(pageInfo)
        context.saveGState()
        context.translateBy(x: 0, y: page.height)
        context.scaleBy(x: 1, y: -1)
        PageImage.drawUnderInk(page, rect: media, paper: paper, pixel: 1 / inkScale, in: context, load: load)
        context.restoreGState()
        var top: CGFloat = 0
        while top < page.height {
            let height = min(band, page.height - top)
            let rect = CGRect(x: 0, y: top, width: page.width, height: height)
            if let ink = PageImage.inkImage(page, rect: rect, scale: inkScale, load: load) {
                context.draw(ink, in: CGRect(x: 0, y: page.height - top - height, width: page.width, height: height))
            }
            top += height
        }
        context.endPDFPage()
    }
}
