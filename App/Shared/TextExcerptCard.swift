import InkhashCore
import SwiftUI

/// What an element draws besides its own geometry: the photo of an image, the card of an excerpt.
@MainActor
enum ElementContent {
    static func image(for element: PageElement, load: (String) -> Data?) -> CGImage? {
        switch element.kind {
        case .image: ElementImages.shared.image(for: element.blob, load: load)
        case .excerpt: ExcerptElementImages.shared.image(for: element)
        case .shape, .tape, .link: nil
        }
    }
}

/// Cards of excerpt elements on pages, drawn from the current workspace. See ADR 0037.
@MainActor
final class ExcerptElementImages {
    static let shared = ExcerptElementImages()
    private var cache: [String: CGImage] = [:]

    func image(for element: PageElement) -> CGImage? {
        guard let target = element.excerptTarget else { return nil }
        let source = ExcerptSource.current
        let note = source.note(target.noteID)
        let key = [target.target, "\(element.width)x\(element.height)", note?.updatedAt ?? "-"].joined(separator: "|")
        if let cached = cache[key] { return cached }
        let caption = Self.caption(for: target, note: note)
        guard let card = ExcerptCards.card(for: target, caption: caption, source: source, width: element.width, height: element.height) else { return nil }
        if cache.count > 64 { cache.removeAll() }
        cache[key] = card.image
        return card.image
    }

    /// Height of the card at `width`, for placing a new element.
    func naturalHeight(of target: ExcerptTarget, width: Double, limit: Double = 560) -> Double {
        let source = ExcerptSource.current
        let caption = Self.caption(for: target, note: source.note(target.noteID))
        let size = ExcerptCards.card(for: target, caption: caption, source: source, width: width, height: nil)?.size
        return min(Double(size?.height ?? 200), limit)
    }

    static func caption(for target: ExcerptTarget, note: Note?) -> String {
        let title = note?.displayTitle ?? Note.untitled
        if case let .text(excerpt) = target, let section = excerpt.section { return "\(title) · \(section)" }
        return title
    }
}

/// A text excerpt as it stands on the page: the text, a quiet rule on the left, the source below.
/// Like the handwriting card in text notes, no box around it. See ADR 0032 and 0035.
struct TextExcerptCard: View {
    enum Content {
        case text(blocks: [Block], caption: String)
        case missing(String)
    }

    var content: Content
    var width: Double
    /// Nil measures; otherwise the text is cut off with a fade.
    var height: Double?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule()
                .fill(isMissing ? Ink.muted.opacity(0.25) : Ink.accent.opacity(0.4))
                .frame(width: 2.5)
            VStack(alignment: .leading, spacing: 6) {
                switch content {
                case let .text(blocks, caption):
                    body(of: blocks)
                        .frame(maxHeight: height.map { max($0 - 30, 20) }, alignment: .top)
                        .clipped()
                        .mask(fade)
                    captionView(caption, symbol: "doc.text")
                case let .missing(reason):
                    captionView(reason, symbol: "doc.text")
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: width, height: height.map { CGFloat($0) }, alignment: .topLeading)
    }

    private var isMissing: Bool {
        if case .missing = content { return true }
        return false
    }

    private var fade: some View {
        LinearGradient(stops: [.init(color: .black, location: 0.82), .init(color: .black.opacity(height == nil ? 1 : 0), location: 1)], startPoint: .top, endPoint: .bottom)
    }

    private func captionView(_ text: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12))
        .foregroundStyle(Ink.muted)
    }

    private func body(of blocks: [Block]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                Self.line(block, number: Self.number(at: index, in: blocks))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Ink.ink)
    }

    /// One block as it reads, the same in the card and in the picker's preview.
    @ViewBuilder
    static func line(_ block: Block, number: Int) -> some View {
        switch block.type {
        case .heading1: inline(block.spans).font(.system(size: 20, weight: .semibold, design: .serif))
        case .heading2: inline(block.spans).font(.system(size: 17, weight: .semibold, design: .serif))
        case .heading3: inline(block.spans).font(.system(size: 15, weight: .semibold, design: .serif))
        case .bullet: marked("•", block)
        case .numbered: marked("\(number).", block)
        case .checkbox:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: block.checked ? "checkmark.square" : "square")
                    .foregroundStyle(Ink.muted)
                inline(block.spans).strikethrough(block.checked, color: Ink.muted)
            }
            .font(.system(size: 14, design: .serif))
        case .code:
            Text(block.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.muted.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        case .tableRow:
            HStack(spacing: 0) {
                ForEach(Array(MarkdownCodec.tableCells(block.spans).enumerated()), id: \.offset) { _, cell in
                    inline(cell).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(size: 13, design: .serif))
        case .excerpt:
            Label(block.plain, systemImage: "scribble").font(.system(size: 13)).foregroundStyle(Ink.muted)
        case .paragraph:
            inline(block.spans).font(.system(size: 14, design: .serif))
        }
    }

    private static func marked(_ marker: String, _ block: Block) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker).foregroundStyle(Ink.muted)
            inline(block.spans)
        }
        .font(.system(size: 14, design: .serif))
    }

    private static func inline(_ spans: [InlineSpan]) -> Text {
        spans.reduce(Text("")) { text, span in
            var piece = Text(span.text)
            if span.bold { piece = piece.bold() }
            if span.italic { piece = piece.italic() }
            if span.code { piece = piece.font(.system(size: 13, design: .monospaced)) }
            if span.link != nil { piece = piece.foregroundColor(Ink.accent) }
            return text + piece
        }
    }

    static func number(at index: Int, in blocks: [Block]) -> Int {
        var count = 1
        var cursor = index - 1
        while cursor >= 0, blocks[cursor].type == .numbered {
            count += 1
            cursor -= 1
        }
        return count
    }
}
