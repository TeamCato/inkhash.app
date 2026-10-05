import XCTest
@testable import InkhashCore

final class SearchTests: XCTestCase {
    func testEmptyQueryMatchesNothing() {
        XCTAssertTrue(NoteSearch.search("   ", in: [sample]).isEmpty)
    }

    func testOrderDoesNotMatter() {
        let hits = NoteSearch.search("projekt plan", in: [sample])
        XCTAssertEqual(hits.map(\.id), [sample.id])
    }

    func testFuzzyRecognitionError() {
        let hits = NoteSearch.search("proiekt", in: [sample])
        XCTAssertEqual(hits.map(\.id), [sample.id])
    }

    func testTagWithoutHash() {
        let hits = NoteSearch.search("alpen", in: [sample])
        XCTAssertEqual(hits.map(\.id), [sample.id])
        let hashed = NoteSearch.search("#alpen", in: [sample])
        XCTAssertEqual(hashed.map(\.id), [sample.id])
    }

    func testShortTokenDoesNotPrefixMatch() {
        XCTAssertTrue(NoteSearch.search("ab", in: [sample]).isEmpty)
    }

    func testDiacriticsAndEszett() {
        let note = SearchDocument(id: UUID(), title: "Straße", body: "Über den Pass", tags: [])
        XCTAssertEqual(NoteSearch.search("strasse", in: [note]).count, 1)
        XCTAssertEqual(NoteSearch.search("uber", in: [note]).count, 1)
    }

    func testAllQueryWordsMustMatch() {
        XCTAssertTrue(NoteSearch.search("projekt kapstadt", in: [sample]).isEmpty)
    }

    func testTagRanksAboveAWeakBodyMatch() throws {
        let tagged = SearchDocument(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, title: "Notiz", body: "etwas anderes", tags: ["alpen"])
        let fuzzy = SearchDocument(id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, title: "Notiz", body: "alpenwanderweg später", tags: [])
        let hits = NoteSearch.search("alpen", in: [fuzzy, tagged])
        XCTAssertEqual(hits.first?.id, tagged.id)
    }

    private var sample: SearchDocument {
        SearchDocument(
            id: UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!,
            title: "Plan für das Projekt",
            body: "Morgen in die Alpen",
            tags: ["alpen"]
        )
    }
}
