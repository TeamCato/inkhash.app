import XCTest
@testable import InkhashCore

final class NoteListingTests: XCTestCase {
    private func record(_ markdown: String, folder: String = "", at time: String, favorite: Bool = false, deleted: Bool = false) -> NoteRecord {
        var note = Note.newText(now: time)
        note.applyMarkdown(markdown)
        note.folder = folder
        note.favorite = favorite
        note.updatedAt = time
        if deleted { note.deletedAt = time }
        return NoteRecord(note: note, dirty: false, conflict: false)
    }

    func testSectionsAreNewestFirst() {
        let old = record("Alt #reise\n", at: "2026-10-01T06:00:00Z", favorite: true)
        let new = record("Neu #reise #rad\n", folder: "Reisen", at: "2026-10-02T06:00:00Z")
        let gone = record("Weg\n", at: "2026-10-03T06:00:00Z", deleted: true)
        let listing = NoteListing(records: [old, gone, new], keptFolders: ["Rezepte"])

        XCTAssertEqual(listing.listed(.notes, query: "").map(\.id), [new.id, old.id])
        XCTAssertEqual(listing.listed(.favorites, query: "").map(\.id), [old.id])
        XCTAssertEqual(listing.listed(.trash, query: "").map(\.id), [gone.id])
        XCTAssertEqual(listing.trashCount, 1)
        XCTAssertEqual(listing.folders, ["Reisen", "Rezepte"])
        XCTAssertEqual(listing.tagCounts, [TagCount(tag: "reise", count: 2), TagCount(tag: "rad", count: 1)])
    }

    func testTagFilterNarrowsTheTree() {
        let bike = record("Rad #rad\n", folder: "Sport", at: "2026-10-01T06:00:00Z")
        let trip = record("Reise #reise\n", folder: "Reisen", at: "2026-10-02T06:00:00Z")
        let listing = NoteListing(records: [bike, trip], keptFolders: ["Leer"])

        XCTAssertEqual(NoteListing.tagFilter(" #Ra "), "ra")
        XCTAssertNil(NoteListing.tagFilter("rad"))
        XCTAssertEqual(listing.suggestedTags(query: "#re").map(\.tag), ["reise"])
        XCTAssertEqual(listing.suggestedTags(query: "rad"), [])

        let all = listing.folderTree(query: "")
        XCTAssertEqual(all.folders.map(\.path), ["Leer", "Reisen", "Sport"])
        let filtered = listing.folderTree(query: "#ra")
        XCTAssertEqual(filtered.folders.map(\.path), ["Sport"])
        XCTAssertEqual(filtered.folders.first?.notes.map(\.id), [bike.id])
    }

    func testLinkableFoldsCaseAndAccents() {
        let cafe = record("Café Plan\n", at: "2026-10-01T06:00:00Z")
        let other = record("Anderes\n", at: "2026-10-02T06:00:00Z")
        let gone = record("Cafe alt\n", at: "2026-10-03T06:00:00Z", deleted: true)
        let listing = NoteListing(records: [cafe, other, gone], keptFolders: [])

        XCTAssertEqual(listing.linkable(matching: "cafe").map(\.id), [cafe.id])
        XCTAssertEqual(listing.linkable(matching: "").map(\.id), [other.id, cafe.id])
        XCTAssertEqual(listing.linkable(matching: "", excluding: other.id).map(\.id), [cafe.id])
        XCTAssertEqual(listing.linkable(matching: "", limit: 1).map(\.id), [other.id])
    }
}
