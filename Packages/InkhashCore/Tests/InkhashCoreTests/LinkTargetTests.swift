import XCTest
@testable import InkhashCore

final class LinkTargetTests: XCTestCase {
    func testAddressesGetAScheme() {
        XCTAssertEqual(LinkTarget.normalize("example.com"), "https://example.com")
        XCTAssertEqual(LinkTarget.normalize("  example.com/a?b=1 "), "https://example.com/a?b=1")
        XCTAssertEqual(LinkTarget.normalize("example.com:8080/x"), "https://example.com:8080/x")
        XCTAssertEqual(LinkTarget.normalize("name@example.com"), "mailto:name@example.com")
    }

    func testAllowedSchemesStay() {
        XCTAssertEqual(LinkTarget.normalize("https://example.com"), "https://example.com")
        XCTAssertEqual(LinkTarget.normalize("HTTP://example.com/A"), "http://example.com/A")
        XCTAssertEqual(LinkTarget.normalize("mailto:a@b.de"), "mailto:a@b.de")
        let id = UUID()
        XCTAssertEqual(LinkTarget.normalize("inkhash://note/\(id.uuidString)"), NoteLink.target(for: id))
    }

    func testWhatCannotBeALink() {
        for input in ["", "   ", "zwei wörter", "ftp://example.com", "javascript:alert(1)", "tel:123",
                      "https://", "mailto:", "inkhash://note/nicht-uuid", "nur", ".com", "/pfad"] {
            XCTAssertNil(LinkTarget.normalize(input), input)
        }
        XCTAssertNil(LinkTarget.normalize("https://example.com/" + String(repeating: "a", count: 2000)))
    }

    /// Every normalized target must pass the server's prefix check and survive the Markdown codec.
    func testNormalizedTargetsRoundTripThroughMarkdown() {
        for input in ["example.com/wiki/A_(B)", "a@b.de", "https://example.com/x?y=1#z"] {
            guard let target = LinkTarget.normalize(input) else { return XCTFail(input) }
            XCTAssertTrue(["https://", "http://", "mailto:", NoteLink.prefix].contains { target.hasPrefix($0) }, target)
            let markdown = MarkdownCodec.serializeInline([InlineSpan(text: "Label", link: target)])
            XCTAssertEqual(MarkdownCodec.parseInline(markdown).spans.map(\.link), [target], markdown)
        }
    }

    func testLooksLikeAddress() {
        XCTAssertTrue(LinkTarget.looksLikeAddress("example.com"))
        XCTAssertTrue(LinkTarget.looksLikeAddress("a@b.de"))
        XCTAssertFalse(LinkTarget.looksLikeAddress("Einkaufsliste"))
        XCTAssertFalse(LinkTarget.looksLikeAddress("Treffen 3.4."))
    }

    func testDefaultLabel() {
        XCTAssertEqual(LinkTarget.defaultLabel(for: "https://www.example.com/a"), "example.com")
        XCTAssertEqual(LinkTarget.defaultLabel(for: "mailto:a@b.de"), "a@b.de")
    }
}
