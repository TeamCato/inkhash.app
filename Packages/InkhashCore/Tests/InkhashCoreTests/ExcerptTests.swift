import XCTest
@testable import InkhashCore

/// ADR 0032: excerpts of handwriting in text notes.
final class ExcerptTests: XCTestCase {
    private let noteID = UUID(uuidString: "6F1C3A2E-7B64-4D1A-9C3E-2A8B0D5E7F10")!
    private let pageID = UUID(uuidString: "0A0B0C0D-1111-2222-3333-444455556666")!
    private var target: String {
        "inkhash://note/6f1c3a2e-7b64-4d1a-9c3e-2a8b0d5e7f10/page/0a0b0c0d-1111-2222-3333-444455556666?rect=10,20.5,300.25,120"
    }

    func testTargetRoundTrip() throws {
        let excerpt = try XCTUnwrap(Excerpt(target: target))
        XCTAssertEqual(excerpt.noteID, noteID)
        XCTAssertEqual(excerpt.pageID, pageID)
        XCTAssertEqual([excerpt.x, excerpt.y, excerpt.width, excerpt.height], [10, 20.5, 300.25, 120])
        XCTAssertEqual(excerpt.target, target)
        XCTAssertEqual(Excerpt(target: target.uppercased().replacingOccurrences(of: "INKHASH://NOTE/", with: "inkhash://note/").replacingOccurrences(of: "/PAGE/", with: "/page/").replacingOccurrences(of: "?RECT=", with: "?rect="))?.target, target)
    }

    func testNumbersAreRoundedToTwoDecimals() throws {
        let excerpt = try XCTUnwrap(Excerpt(noteID: noteID, pageID: pageID, x: 1.234, y: 0, width: 99.999, height: 5.1))
        XCTAssertTrue(excerpt.target.hasSuffix("?rect=1.23,0,100,5.1"), excerpt.target)
    }

    func testInvalidTargets() {
        let base = "inkhash://note/\(noteID.uuidString)"
        for candidate in [
            base,
            "\(base)/page/\(pageID.uuidString)",
            "\(base)/page/\(pageID.uuidString)?rect=1,2,3",
            "\(base)/page/\(pageID.uuidString)?rect=1,2,0,4",
            "\(base)/page/\(pageID.uuidString)?rect=-1,2,3,4",
            "\(base)/page/\(pageID.uuidString)?rect=1,2,nan,4",
            "\(base)/page/kein-uuid?rect=1,2,3,4",
            "\(base)/seite/\(pageID.uuidString)?rect=1,2,3,4",
            "https://example.com/page/\(pageID.uuidString)?rect=1,2,3,4",
        ] {
            XCTAssertNil(Excerpt(target: candidate), candidate)
        }
    }

    func testExcerptIsNoPlainNoteLink() {
        XCTAssertNil(NoteLink.noteID(in: target))
        XCTAssertTrue(LinkTarget.isAccepted(target))
    }

    func testClippedToPage() throws {
        let excerpt = try XCTUnwrap(Excerpt(target: target))
        let clipped = try XCTUnwrap(excerpt.clipped(toWidth: 200, height: 100))
        XCTAssertEqual([clipped.x, clipped.y, clipped.width, clipped.height], [10, 20.5, 190, 79.5])
        XCTAssertNil(excerpt.clipped(toWidth: 5, height: 1000))
    }

    func testParagraphRoundTrip() throws {
        let markdown = "Vorher\n\n![Skizze **Lager**](\(target))\n\nNachher\n"
        let blocks = MarkdownCodec.parse(markdown)
        XCTAssertEqual(blocks.map(\.type), [.paragraph, .excerpt, .paragraph])
        XCTAssertEqual(blocks[1].plain, "Skizze Lager")
        XCTAssertEqual(MarkdownCodec.excerpt(in: blocks[1]), .page(try XCTUnwrap(Excerpt(target: target))))
        XCTAssertEqual(MarkdownCodec.serialize(blocks), "Vorher\n\n![Skizze Lager](\(target))\n\nNachher\n")
    }

    func testEmptyLabelBecomesDefault() throws {
        let excerpt = try XCTUnwrap(Excerpt(target: target))
        let markdown = MarkdownCodec.serialize([MarkdownCodec.excerptBlock(excerpt, label: "  ")])
        XCTAssertEqual(markdown, "![Ausschnitt](\(target))\n")
    }

    func testWhatStaysText() {
        for line in [
            "Siehe ![Skizze](\(target))",
            "![Skizze](\(target)) danach",
            "![Bild](https://example.com/a.png)",
            "![Notiz](inkhash://note/\(noteID.uuidString.lowercased()))",
            "![](\(target))",
        ] {
            let blocks = MarkdownCodec.parse(line)
            XCTAssertEqual(blocks.map(\.type), [.paragraph], line)
        }
    }

    func testExcerptDoesNotMakeTheTitle() {
        let markdown = "![Skizze](\(target))\n\nProtokoll vom Montag\n"
        XCTAssertEqual(MarkdownCodec.title(for: markdown), "Protokoll vom Montag")
    }

    func testSplitBehindAnExcerptStartsAParagraph() throws {
        let block = MarkdownCodec.excerptBlock(try XCTUnwrap(Excerpt(target: target)), label: "Skizze")
        let (left, right) = MarkdownCodec.split(block, atUTF16: (block.plain as NSString).length)
        XCTAssertEqual(left.type, .excerpt)
        XCTAssertEqual(right.type, .paragraph)
    }

    /// An older version reads the line as `!` plus a link and must write it back unchanged.
    func testOlderReadingAsInlineLinkKeepsTheLine() {
        let line = "![Skizze Lager](\(target))"
        let parsed = MarkdownCodec.parseInline(line)
        XCTAssertEqual(parsed.spans.map(\.link), [nil, target])
        XCTAssertEqual(MarkdownCodec.serializeInline(parsed.spans), line)
    }
}

/// ADR 0035 and 0037: text excerpts and excerpts on pages.
final class TextExcerptTests: XCTestCase {
    private let markdown = """
    # Projekt

    Einleitung

    ## Ziele

    - schnell
    - leise

    ### Detail

    Mehr

    ## Risiken

    Wetter
    """

    func testSectionRunsToTheNextHeadingOfTheSameLevel() throws {
        let blocks = try XCTUnwrap(MarkdownCodec.section(of: markdown, heading: "Ziele"))
        XCTAssertEqual(blocks.map(\.plain), ["Ziele", "schnell", "leise", "Detail", "Mehr"])
    }

    func testWholeNoteAndMissingHeading() {
        XCTAssertEqual(MarkdownCodec.section(of: markdown, heading: nil)?.count, MarkdownCodec.parse(markdown).count)
        XCTAssertNil(MarkdownCodec.section(of: markdown, heading: "Gibt es nicht"))
        XCTAssertEqual(MarkdownCodec.headings(in: markdown), ["Projekt", "Ziele", "Detail", "Risiken"])
    }

    func testTextTargetRoundTrip() throws {
        let id = UUID()
        let whole = TextExcerpt(noteID: id)
        XCTAssertEqual(whole.target, "inkhash://note/\(id.uuidString.lowercased())?text")
        let section = TextExcerpt(noteID: id, section: "Ziele (neu)")
        XCTAssertEqual(section.target, "inkhash://note/\(id.uuidString.lowercased())?text&section=Ziele%20%28neu%29")
        let range = TextExcerpt(noteID: id, from: "Erste Zeile", to: "Letzte\tZelle")
        XCTAssertEqual(TextExcerpt(target: range.target), range)
        XCTAssertEqual(range.to, "Letzte Zelle")
        for excerpt in [whole, section, range] {
            XCTAssertEqual(ExcerptTarget(target: excerpt.target), .text(excerpt))
            XCTAssertTrue(LinkTarget.isAccepted(excerpt.target))
            XCTAssertNil(NoteLink.noteID(in: excerpt.target))
            // The Markdown codec carries it as a link target: no spaces, no parentheses.
            XCTAssertNil(excerpt.target.rangeOfCharacter(from: CharacterSet(charactersIn: " ()")))
        }
        XCTAssertNil(TextExcerpt(target: "inkhash://note/\(id.uuidString)?page"))
        XCTAssertNil(TextExcerpt(target: "inkhash://note/\(id.uuidString)"))
    }

    func testTextExcerptBlocks() throws {
        let id = UUID()
        let range = try XCTUnwrap(MarkdownCodec.blocks(for: TextExcerpt(noteID: id, from: "schnell", to: "Detail"), in: markdown))
        XCTAssertEqual(range.map(\.plain), ["schnell", "leise", "Detail"])
        let single = try XCTUnwrap(MarkdownCodec.blocks(for: TextExcerpt(noteID: id, from: "Wetter"), in: markdown))
        XCTAssertEqual(single.map(\.plain), ["Wetter"])
        XCTAssertNil(MarkdownCodec.blocks(for: TextExcerpt(noteID: id, from: "fehlt"), in: markdown))
        XCTAssertEqual(MarkdownCodec.blocks(for: TextExcerpt(noteID: id, section: "Risiken"), in: markdown)?.count, 2)
    }

    func testTextExcerptParagraphInText() {
        let excerpt = TextExcerpt(noteID: UUID(), section: "Ziele")
        let source = "![Ziele](\(excerpt.target))\n"
        let blocks = MarkdownCodec.parse(source)
        XCTAssertEqual(MarkdownCodec.excerpt(in: blocks[0]), .text(excerpt))
        XCTAssertEqual(MarkdownCodec.serialize(blocks), source)
    }

    func testElementRoundTrip() throws {
        let target = ExcerptTarget.text(TextExcerpt(noteID: UUID(), section: "Ziele"))
        let element = PageElement.excerpt(target, center: (x: 300, y: 200), width: 360, height: 240)
        XCTAssertEqual(element.kind, .excerpt)
        XCTAssertEqual(element.excerptTarget, target)
        let data = try JSONEncoder().encode(element)
        XCTAssertEqual(try JSONDecoder().decode(PageElement.self, from: data), element)
    }
}
