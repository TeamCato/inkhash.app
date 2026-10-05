// Spike for ADR 0024 and 0041: converts a PDF export or a .goodnotes notebook into PKDrawing
// blobs and PNG previews.
//
//   make import-spike FILE=path/to/export.pdf
//   make import-spike FILE=path/to/notebook.goodnotes
//
// Writes into .build/import-spike/<name>/: page-N.drawing (PKDrawing bytes, what a blob would be),
// page-N.png (how PencilKit renders it), and a summary on stdout. Compiled with swiftc next to
// PDFInk.swift and InkImport.swift, like tools/RenderIcon.swift is.

import AppKit
import Foundation
import PencilKit

@main
struct PdfInkSpike {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else {
            FileHandle.standardError.write(Data("usage: pdf-ink-spike <file.pdf> <out-dir>\n".utf8))
            exit(2)
        }
        let source = URL(fileURLWithPath: arguments[1])
        let outDir = URL(fileURLWithPath: arguments[2])
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let data = try Data(contentsOf: source)
        if data.starts(with: [0x50, 0x4B]) {
            try goodNotes(data, name: source.lastPathComponent, outDir: outDir)
            return
        }
        let raw = try PDFInk.pages(from: data)
        let pages = PDFInk.withoutRepeated(raw)

        print("\(source.lastPathComponent): \(pages.count) Seiten")
        for (index, page) in pages.enumerated() {
            let before = raw[index].strokes.count
            let filled = page.strokes.filter(\.filled).count
            let ribbons = page.strokes.filter { $0.filled && !$0.centerline().filled }.count
            let drawing = InkImport.drawing(from: page)
            let bytes = drawing.dataRepresentation()
            let number = index + 1
            try bytes.write(to: outDir.appendingPathComponent("page-\(number).drawing"))
            try png(drawing, width: page.width, height: page.height)
                .write(to: outDir.appendingPathComponent("page-\(number).png"))
            print(
                "  Seite \(number): \(Int(page.width))×\(Int(page.height)), "
                    + "\(page.strokes.count) Pfade (\(before - page.strokes.count) Vorlage entfernt), "
                    + "\(filled) gefüllt, davon \(ribbons) als Band erkannt, "
                    + "\(page.skippedForms) XObjects übersprungen, \(bytes.count) Bytes PKDrawing"
            )
        }
        print("Ergebnis in \(outDir.path)")
    }

    private static func goodNotes(_ data: Data, name: String, outDir: URL) throws {
        let notebook = try InkImport.notebook(fromGoodNotes: data)
        print("\(name): \(notebook.pages.count) Seiten, Titel \(notebook.title ?? "–"), \(notebook.skipped) Elemente übersprungen")
        for (index, page) in notebook.pages.enumerated() {
            let number = index + 1
            try page.data.write(to: outDir.appendingPathComponent("page-\(number).drawing"))
            let drawing = try PKDrawing(data: page.data)
            try png(drawing, width: page.width, height: page.height, images: page.images)
                .write(to: outDir.appendingPathComponent("page-\(number).png"))
            print("  Seite \(number): \(Int(page.width))×\(Int(page.height)), \(drawing.strokes.count) Striche, \(page.images.count) Bilder, \(page.data.count) Bytes PKDrawing")
        }
        print("Ergebnis in \(outDir.path)")
    }

    /// Images are drawn under the ink on white, like the page does it.
    private static func png(_ drawing: PKDrawing, width: Double, height: Double, images: [(element: PageElement, jpeg: Data)] = []) throws -> Data {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let image = NSImage(size: rect.size, flipped: true) { _ in
            NSColor.white.setFill()
            rect.fill()
            for item in images.sorted(by: { $0.element.z < $1.element.z }) {
                guard let picture = NSImage(data: item.jpeg), let context = NSGraphicsContext.current?.cgContext else { continue }
                let e = item.element
                context.saveGState()
                context.translateBy(x: e.x, y: e.y)
                context.rotate(by: e.rotation)
                picture.draw(in: CGRect(x: -e.width / 2, y: -e.height / 2, width: e.width, height: e.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                context.restoreGState()
            }
            drawing.image(from: rect, scale: 2).draw(in: rect)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PdfInkSpike", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG fehlgeschlagen"])
        }
        return png
    }
}
