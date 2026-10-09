import CoreGraphics
import InkhashCore
import PencilKit
import XCTest
@testable import Inkhash

@MainActor
final class ExportTests: LibraryTestCase {
    private func inkNote(pages: Int, height: Double = PageGeometry.height) throws -> Note {
        let drawing = try store.putBlob(PKDrawing().dataRepresentation())
        let all = (0..<pages).map { _ in InkPage(blob: drawing, height: height) }
        var note = Note.newInk(page: all[0], now: "2026-10-01T08:00:00Z")
        note.pages = all
        note.title = "Skizze"
        try store.save(note: note, meta: .clean)
        library.reload()
        return note
    }

    func testHandwritingBecomesAPDFWithOnePagePerPage() throws {
        let note = try inkNote(pages: 3, height: 2500)
        let data = try XCTUnwrap(NotePDF.data(for: note) { self.library.drawingData(for: $0) })
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(document.numberOfPages, 3)
        let box = try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.height, 2500)
        XCTAssertEqual(box.width, PageGeometry.width)
    }

    func testTextHasNoPDFButMarkdown() throws {
        let note = try syncedText("# Plan\n**fett**\n")
        XCTAssertNil(NotePDF.data(for: note) { _ in nil })
        let url = try NoteExport.file(for: note) { _ in nil }
        XCTAssertEqual(url.lastPathComponent, "Plan.md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# Plan\n**fett**\n")
    }

    func testWorkspaceExportImportsBackIntoAnotherWorkspace() throws {
        let text = try syncedText("# Plan\n")
        let ink = try inkNote(pages: 1)
        let (url, summary) = try WorkspaceExporter.export(registry.current, store: store)
        XCTAssertEqual(summary.notes, 2)
        XCTAssertEqual(summary.withoutPDF, 0)

        let other = Workspace(name: "Leer")
        registry.append(other)
        XCTAssertTrue(registry.select(other.id))
        library.reload()
        XCTAssertTrue(library.records.isEmpty)
        var told = 0
        library.changed = { told += 1 }
        XCTAssertNotNil(library.importFile(at: url) { $0 })
        XCTAssertEqual(Set(library.records.map(\.id)), [text.id, ink.id])
        XCTAssertTrue(library.records.allSatisfy { $0.dirty && $0.note.revision == 0 })
        XCTAssertEqual(told, 1)
    }

    func testLibraryLivesWhereTheDeviceBackupLooks() throws {
        let base = AppModel.storageBase
        XCTAssertTrue(base.path.contains("Library/Application Support"), base.path)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let excluded = try base.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertNotEqual(excluded, true)
    }
}
