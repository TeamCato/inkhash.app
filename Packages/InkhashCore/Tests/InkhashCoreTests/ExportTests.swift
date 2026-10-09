import XCTest
@testable import InkhashCore

final class ZipWriterTests: XCTestCase {
    func testWrittenArchiveReadsBack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        let zip = try ZipWriter(url: url)
        try zip.add("a.txt", data: Data("eins".utf8))
        try zip.add("Ordner/Überschrift ü.md", data: Data("# zwei\n".utf8))
        try zip.add("leer", data: Data())
        try zip.finish()
        let archive = try ZipArchive(Data(contentsOf: url))
        XCTAssertEqual(try archive.read("a.txt"), Data("eins".utf8))
        XCTAssertEqual(try archive.read("Ordner/Überschrift ü.md"), Data("# zwei\n".utf8))
        XCTAssertEqual(try archive.read("leer"), Data())
        XCTAssertEqual(archive.entries.count, 3)
    }

    func testTheSameNameTwiceIsRefused() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        let zip = try ZipWriter(url: url)
        try zip.add("a", data: Data())
        XCTAssertThrowsError(try zip.add("a", data: Data()))
        XCTAssertThrowsError(try zip.add("/abs", data: Data()))
    }

    func testCRC32MatchesTheStandard() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }
}

final class ExportNamesTests: XCTestCase {
    func testFileNamesAreSafe() {
        XCTAssertEqual(ExportNames.fileName("Plan: A/B?"), "Plan A B")
        XCTAssertEqual(ExportNames.fileName("..versteckt"), "versteckt")
        XCTAssertEqual(ExportNames.fileName("Ende."), "Ende")
        XCTAssertEqual(ExportNames.fileName("  \n "), Note.untitled)
        XCTAssertEqual(ExportNames.fileName("Zeile\nzwei"), "Zeile zwei")
        XCTAssertEqual(ExportNames.fileName(String(repeating: "x", count: 200)).count, ExportNames.maxLength)
    }

    func testFolderPathsKeepTheirSegments() {
        XCTAssertEqual(ExportNames.folderPath("Projekt/Treffen"), "Projekt/Treffen")
        XCTAssertEqual(ExportNames.folderPath("A:B/C"), "A B/C")
        XCTAssertEqual(ExportNames.folderPath(""), "")
    }

    func testNamerNumbersTakenNamesIgnoringCase() {
        var namer = ExportNames.Namer()
        XCTAssertEqual(namer.path(in: "Notizen", name: "Plan", ext: "md"), "Notizen/Plan.md")
        XCTAssertEqual(namer.path(in: "Notizen", name: "plan", ext: "md"), "Notizen/plan 2.md")
        XCTAssertEqual(namer.path(in: "Notizen", name: "Plan", ext: "pdf"), "Notizen/Plan.pdf")
        XCTAssertEqual(namer.path(in: "", name: "Plan", ext: "md"), "Plan.md")
    }
}

@MainActor
final class WorkspaceExportTests: XCTestCase {
    private var urls: [URL] = []

    override func tearDown() async throws {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    private func temporary(_ ext: String = "") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ext)
        urls.append(url)
        return url
    }

    private func store() throws -> LocalStore {
        try LocalStore(root: temporary())
    }

    private func sample(in store: LocalStore) throws -> (text: Note, ink: Note, trashed: Note) {
        var text = Note.newText(now: "2026-10-01T08:00:00Z")
        text.applyMarkdown("# Plan\nerster #punkt\n")
        text.folder = "Projekt/Treffen"
        text.revision = 3
        let drawing = try store.putBlob(Data("strokes".utf8))
        let photo = try store.putBlob(Data("jpeg".utf8))
        var page = InkPage(blob: drawing, transcript: "Skizze")
        page.elements = [PageElement(kind: .image, x: 10, y: 10, width: 20, height: 20, blob: photo)]
        var ink = Note.newInk(page: page, now: "2026-10-01T08:00:00Z")
        ink.transcript = "Skizze"
        var trashed = Note.newText(now: "2026-10-01T08:00:00Z")
        trashed.applyMarkdown("# Weg\n")
        trashed.deletedAt = "2026-10-02T08:00:00Z"
        for note in [text, ink, trashed] { try store.save(note: note, meta: .clean) }
        return (text, ink, trashed)
    }

    private func export(_ source: LocalStore, pdf: @escaping (Note) -> Data? = { _ in Data("%PDF".utf8) }) throws -> (URL, WorkspaceExport.Summary) {
        let url = temporary(".zip")
        let summary = try WorkspaceExport.write(
            to: url, workspace: "Privat", notes: try source.list().map(\.note), now: "2026-10-09T10:00:00Z",
            blob: { try source.blob($0) }, pdf: pdf
        )
        return (url, summary)
    }

    func testExportHoldsReadableFilesAndTheAppCopy() throws {
        let source = try store()
        let (text, ink, _) = try sample(in: source)
        let (url, summary) = try export(source)
        XCTAssertEqual(summary, WorkspaceExport.Summary(notes: 2, withoutPDF: 0))
        let archive = try ZipArchive(Data(contentsOf: url))
        XCTAssertEqual(try archive.read("Notizen/Projekt/Treffen/Plan.md"), Data(text.markdown!.utf8))
        XCTAssertEqual(try archive.read("Notizen/Skizze.pdf"), Data("%PDF".utf8))
        XCTAssertNotNil(try archive.read("inkhash/notes/\(text.id.uuidString.lowercased()).json"))
        XCTAssertNotNil(try archive.read("inkhash/notes/\(ink.id.uuidString.lowercased()).json"))
        XCTAssertEqual(archive.entries.keys.filter { $0.hasPrefix("inkhash/blobs/") }.count, 2)
        XCTAssertFalse(archive.entries.keys.contains { $0.contains("Weg") })
        let manifest = try InkhashJSON.decode(WorkspaceExport.Manifest.self, from: XCTUnwrap(archive.read(WorkspaceExport.manifestName)))
        XCTAssertEqual(manifest.workspace, "Privat")
        XCTAssertEqual(manifest.notes, 2)
        XCTAssertTrue(WorkspaceExport.isExport(try Data(contentsOf: url)))
    }

    func testMissingPDFIsCountedNotFatal() throws {
        let source = try store()
        _ = try sample(in: source)
        let (url, summary) = try export(source) { _ in nil }
        XCTAssertEqual(summary.withoutPDF, 1)
        XCTAssertEqual(try WorkspaceExport.read(Data(contentsOf: url)).notes.count, 2)
    }

    func testMissingBlobStopsTheExport() throws {
        let source = try store()
        let ink = Note.newInk(page: InkPage(blob: String(repeating: "c", count: 64)))
        try source.save(note: ink, meta: .clean)
        XCTAssertThrowsError(try export(source))
    }

    func testRestoreBringsNotesBackAsNewLocalNotes() throws {
        let source = try store()
        let (text, ink, _) = try sample(in: source)
        let (url, _) = try export(source)
        let target = try store()
        let ids = try WorkspaceExport.restore(try WorkspaceExport.read(Data(contentsOf: url)), into: target, now: "2026-10-09T11:00:00Z")
        XCTAssertEqual(Set(ids), [text.id, ink.id])
        let restored = try XCTUnwrap(target.note(id: text.id))
        XCTAssertEqual(restored.markdown, text.markdown)
        XCTAssertEqual(restored.folder, text.folder)
        XCTAssertEqual(restored.revision, 0)
        XCTAssertEqual(try target.meta(for: text.id), LocalMeta(dirty: true, conflict: false))
        for name in ink.pages![0].blobNames {
            XCTAssertEqual(try target.blob(name), try source.blob(name))
        }
    }

    func testRestoreLeavesEqualNotesAndRenamesTakenIds() throws {
        let source = try store()
        let (text, ink, _) = try sample(in: source)
        let (url, _) = try export(source)
        let target = try store()
        try target.save(note: text, meta: .clean)
        var other = ink
        other.transcript = "ganz anders"
        try target.putBlob(Data("strokes".utf8))
        try target.save(note: other, meta: .clean)
        let ids = try WorkspaceExport.restore(try WorkspaceExport.read(Data(contentsOf: url)), into: target)
        XCTAssertTrue(ids.contains(text.id))
        XCTAssertEqual(try target.meta(for: text.id), .clean)
        XCTAssertFalse(ids.contains(ink.id))
        XCTAssertEqual(try target.note(id: ink.id)?.transcript, "ganz anders")
        XCTAssertEqual(try target.list().count, 3)
    }

    func testDamagedOrForeignArchivesAreRefused() throws {
        let url = temporary(".zip")
        let zip = try ZipWriter(url: url)
        try zip.add("irgendwas.txt", data: Data("x".utf8))
        try zip.finish()
        XCTAssertFalse(WorkspaceExport.isExport(try Data(contentsOf: url)))
        XCTAssertThrowsError(try WorkspaceExport.read(Data(contentsOf: url))) { XCTAssertEqual($0 as? ExportError, .notAnExport) }

        let bad = temporary(".zip")
        let broken = try ZipWriter(url: bad)
        let manifest = WorkspaceExport.Manifest(format: WorkspaceExport.format, version: 1, workspace: "x", exportedAt: "", notes: 0)
        try broken.add(WorkspaceExport.manifestName, data: try InkhashJSON.encode(manifest))
        try broken.add("inkhash/blobs/" + String(repeating: "a", count: 64), data: Data("nicht passend".utf8))
        try broken.finish()
        XCTAssertThrowsError(try WorkspaceExport.read(Data(contentsOf: bad))) { XCTAssertEqual($0 as? ExportError, .damaged) }

        let newer = temporary(".zip")
        let future = try ZipWriter(url: newer)
        let next = WorkspaceExport.Manifest(format: WorkspaceExport.format, version: 99, workspace: "x", exportedAt: "", notes: 0)
        try future.add(WorkspaceExport.manifestName, data: try InkhashJSON.encode(next))
        try future.finish()
        XCTAssertThrowsError(try WorkspaceExport.read(Data(contentsOf: newer))) { XCTAssertEqual($0 as? ExportError, .newerVersion) }
    }
}
