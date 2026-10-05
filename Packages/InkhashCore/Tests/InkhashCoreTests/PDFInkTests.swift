import CoreGraphics
import XCTest
@testable import InkhashCore

final class PDFInkTests: XCTestCase {
    /// A4 page. Draws one stroked line, one filled ribbon, and a "template" line that appears on
    /// both pages. The second page only has the template line.
    private func samplePDF() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            return Data()
        }
        for page in 0..<2 {
            context.beginPDFPage(nil)
            // Template: ruled line across the page, same on every page.
            context.setStrokeColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: 50, y: 700))
            context.addLine(to: CGPoint(x: 545, y: 700))
            context.strokePath()
            if page == 0 {
                // Ballpoint: stroked path, top left area in PDF terms means high y.
                context.setStrokeColor(red: 0, green: 0, blue: 1, alpha: 1)
                context.setLineWidth(2)
                context.move(to: CGPoint(x: 100, y: 800))
                context.addLine(to: CGPoint(x: 200, y: 800))
                context.strokePath()
                // Fountain pen: a horizontal ribbon 4pt thick as a filled polygon.
                context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
                context.move(to: CGPoint(x: 100, y: 600))
                context.addLine(to: CGPoint(x: 150, y: 601))
                context.addLine(to: CGPoint(x: 200, y: 600))
                context.addLine(to: CGPoint(x: 200, y: 604))
                context.addLine(to: CGPoint(x: 150, y: 605))
                context.addLine(to: CGPoint(x: 100, y: 604))
                context.closePath()
                context.fillPath()
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    func testRejectsNonPDF() {
        XCTAssertThrowsError(try PDFInk.pages(from: Data("hallo".utf8)))
    }

    func testReadsPathsScaledAndFlipped() throws {
        let pages = try PDFInk.pages(from: samplePDF())
        XCTAssertEqual(pages.count, 2)
        let first = pages[0]
        XCTAssertEqual(first.width, PageGeometry.width)
        XCTAssertEqual(first.height, 842 * 768 / 595, accuracy: 0.01)
        XCTAssertEqual(first.strokes.count, 3)

        let scale = 768.0 / 595.0
        let line = try XCTUnwrap(first.strokes.first { !$0.filled && $0.color == PDFInkColor(red: 0, green: 0, blue: 1) })
        XCTAssertEqual(line.points.count, 2)
        XCTAssertEqual(line.points[0].x, 100 * scale, accuracy: 0.01)
        // y = 800 in PDF space is near the top after the flip.
        XCTAssertEqual(line.points[0].y, (842 - 800) * scale, accuracy: 0.01)
        XCTAssertEqual(line.width, 2 * scale, accuracy: 0.01)

        let ribbon = try XCTUnwrap(first.strokes.first { $0.filled })
        XCTAssertEqual(ribbon.points.first, ribbon.points.last, "closed polygon repeats its first point")
        XCTAssertEqual(ribbon.color, .black)
    }

    func testCenterlineOfRibbon() throws {
        let pages = try PDFInk.pages(from: samplePDF())
        let ribbon = try XCTUnwrap(pages[0].strokes.first { $0.filled })
        let center = ribbon.centerline()
        XCTAssertFalse(center.filled)
        XCTAssertEqual(center.points.count, 3)
        let scale = 768.0 / 595.0
        XCTAssertEqual(center.points[0].y, (842 - 602) * scale, accuracy: 0.01)
        XCTAssertEqual(center.width, 4 * scale, accuracy: 0.01)
    }

    func testCenterlineLeavesBlobsAlone() {
        // A filled square is not a ribbon.
        let square = PDFInkStroke(
            points: [.init(x: 0, y: 0), .init(x: 10, y: 0), .init(x: 10, y: 10), .init(x: 0, y: 10), .init(x: 0, y: 0), .init(x: 5, y: 0)],
            width: 1, color: .black, filled: true
        )
        XCTAssertEqual(square.centerline(), square)
    }

    func testRepeatedTemplateLinesAreDropped() throws {
        let pages = PDFInk.withoutRepeated(try PDFInk.pages(from: samplePDF()))
        XCTAssertEqual(pages[0].strokes.count, 2)
        XCTAssertEqual(pages[1].strokes.count, 0)
        XCTAssertFalse(pages[0].strokes.contains { $0.color == PDFInkColor(red: 0.8, green: 0.8, blue: 0.8) })
    }

    func testSinglePageKeepsEverything() throws {
        let pages = try PDFInk.pages(from: samplePDF())
        XCTAssertEqual(PDFInk.withoutRepeated([pages[0]])[0].strokes.count, 3)
    }
}
