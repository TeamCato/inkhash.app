// Spike for ADR 0024: converts a PDF export (GoodNotes 6) into PKDrawing blobs and PNG previews.
//
//   make import-spike FILE=path/to/export.pdf
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

    private static func png(_ drawing: PKDrawing, width: Double, height: Double) throws -> Data {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let image = drawing.image(from: rect, scale: 2)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PdfInkSpike", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG fehlgeschlagen"])
        }
        return png
    }
}
