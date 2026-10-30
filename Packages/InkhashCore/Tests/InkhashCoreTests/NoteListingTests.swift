import XCTest
@testable import InkhashCore

final class NoteListingTests: XCTestCase {
    private func record(
        _ markdown: String, folder: String = "", at time: String, favorite: Bool = false, deleted: Bool = false, parent: NoteRecord? = nil
    ) -> NoteRecord {
        var note = Note.newText(now: time)
        note.applyMarkdown(markdown)
        note.folder = folder
        note.parent = parent?.id
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

    func testTreeRowsAreFlatAndSkipCollapsedFolders() {
        let loose = record("Lose\n", at: "2026-10-01T06:00:00Z")
        let retro = record("Retro\n", folder: "projects/retros", at: "2026-10-02T06:00:00Z")
        let plan = record("Plan\n", folder: "projects", at: "2026-10-03T06:00:00Z")
        let workshop = record("Workshop\n", folder: "workshops", at: "2026-10-04T06:00:00Z")
        let tree = NoteListing(records: [loose, retro, plan, workshop], keptFolders: []).folderTree(query: "")

        let open = tree.rows { _ in true }
        XCTAssertEqual(open.map(\.id), [
            "folder:projects", "folder:projects/retros", "note:\(retro.id.uuidString)", "note:\(plan.id.uuidString)",
            "folder:workshops", "note:\(workshop.id.uuidString)",
            "note:\(loose.id.uuidString)",
        ])
        XCTAssertEqual(open.map(\.depth), [0, 1, 2, 1, 0, 1, 0])

        let collapsed = tree.rows { $0 != "projects" }
        XCTAssertEqual(collapsed.map(\.id), [
            "folder:projects",
            "folder:workshops", "note:\(workshop.id.uuidString)",
            "note:\(loose.id.uuidString)",
        ])
        if case .folder(_, let expanded) = collapsed[0].item {
            XCTAssertFalse(expanded)
        } else {
            XCTFail("first row should be the folder")
        }
    }

    func testEmbeddedNotesHangBelowTheirParentAndFold() throws {
        let doc = record("Doc\n", folder: "test", at: "2026-10-01T06:00:00Z")
        let sketch = record("Skizze\n", folder: "test", at: "2026-10-02T06:00:00Z", parent: doc)
        let detail = record("Detail\n", folder: "test", at: "2026-10-03T06:00:00Z", parent: sketch)
        let other = record("Andere\n", folder: "test", at: "2026-10-04T06:00:00Z")
        let tree = NoteListing(records: [doc, sketch, detail, other], keptFolders: []).folderTree(query: "")
        let test = try XCTUnwrap(tree.folders.first)

        XCTAssertEqual(test.notes.map(\.id), [other.id, doc.id])
        XCTAssertEqual(test.noteCount, 4)

        let open = tree.rows { _ in true }
        XCTAssertEqual(open.map(\.id), [
            "folder:test", "note:\(other.id.uuidString)", "note:\(doc.id.uuidString)",
            "note:\(sketch.id.uuidString)", "note:\(detail.id.uuidString)",
        ])
        XCTAssertEqual(open.map(\.depth), [0, 1, 1, 2, 3])
        if case .note(_, let expanded) = open[1].item { XCTAssertNil(expanded) } else { XCTFail("a note") }
        if case .note(_, let expanded) = open[2].item { XCTAssertEqual(expanded, true) } else { XCTFail("a note") }

        let folded = tree.rows { $0 != NoteTree.expansionKey(for: doc.id) }
        XCTAssertEqual(folded.map(\.id), ["folder:test", "note:\(other.id.uuidString)", "note:\(doc.id.uuidString)"])
    }

    func testEmbeddedNoteStandsAloneWithoutItsParentInTheSameFolder() {
        let doc = record("Doc #a\n", folder: "test", at: "2026-10-01T06:00:00Z")
        let moved = record("Weg #b\n", folder: "anders", at: "2026-10-02T06:00:00Z", parent: doc)
        let orphan = record("Waise #b\n", folder: "test", at: "2026-10-03T06:00:00Z", parent: doc)
        let trashedDoc = record("Alt\n", folder: "test", at: "2026-10-04T06:00:00Z", deleted: true)
        let left = record("Übrig #b\n", folder: "test", at: "2026-10-05T06:00:00Z", parent: trashedDoc)
        let listing = NoteListing(records: [doc, moved, orphan, trashedDoc, left], keptFolders: [])

        let tree = listing.folderTree(query: "")
        XCTAssertEqual(tree.folders.map(\.path), ["anders", "test"])
        XCTAssertEqual(tree.folders[0].notes.map(\.id), [moved.id])
        XCTAssertEqual(tree.folders[1].notes.map(\.id), [left.id, doc.id])
        XCTAssertEqual(tree.folders[1].notes[1].children.map(\.id), [orphan.id])

        // A tag filter that leaves the parent out shows the child on its own.
        let filtered = listing.folderTree(query: "#b")
        XCTAssertEqual(filtered.folders[1].notes.map(\.id), [left.id, orphan.id])
    }

    func testFamilyIgnoresLoopsAndFindsDescendants() {
        var a = Note.newText(now: "2026-10-01T06:00:00Z")
        var b = Note.newText(now: "2026-10-01T06:00:00Z")
        var c = Note.newText(now: "2026-10-01T06:00:00Z")
        let d = Note.newText(now: "2026-10-01T06:00:00Z")
        a.parent = b.id
        b.parent = a.id
        c.parent = a.id
        XCTAssertEqual(NoteFamily.parents(among: [a, b, c, d]), [c.id: a.id])

        b.parent = nil
        var e = Note.newText(now: "2026-10-01T06:00:00Z")
        e.parent = c.id
        XCTAssertEqual(NoteFamily.descendants(of: b.id, among: [a, b, c, d, e]), [a.id, c.id, e.id])
        XCTAssertEqual(NoteFamily.descendants(of: d.id, among: [a, b, c, d, e]), [])
    }

    func testParentSurvivesTheWireAndCountsAsContent() throws {
        var child = Note.newText(now: "2026-10-01T06:00:00Z")
        let plain = try JSONEncoder().encode(child)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("parent"))

        let parent = UUID()
        child.parent = parent
        let data = try JSONEncoder().encode(child)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(parent.uuidString.lowercased()))
        let back = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertEqual(back.parent, parent)

        var detached = back
        detached.parent = nil
        XCTAssertFalse(detached.sameContent(as: back))
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
