import InkhashCore
import PencilKit
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Where excerpts find their source: the notes of the current workspace and the blob store. See ADR 0032.
@MainActor
struct ExcerptSource {
    var note: (UUID) -> Note?
    var loadBlob: (String) -> Data?

    static let none = ExcerptSource(note: { _ in nil }, loadBlob: { _ in nil })
    /// The app's workspace, set by the app model. Page elements draw from it.
    static var current = ExcerptSource.none
}

/// Draws the rectangle of a page an excerpt points to: elements under the ink, as on the page.
@MainActor
enum ExcerptRenderer {
    enum Outcome {
        /// The rendered image and the rectangle's size in page points.
        case image(CGImage, size: CGSize)
        /// Why there is nothing to show.
        case placeholder(String)
    }

    static func render(_ excerpt: Excerpt, source: ExcerptSource, scale: CGFloat = 2) -> Outcome {
        guard let note = source.note(excerpt.noteID), note.kind == .ink else {
            return .placeholder("Notiz nicht auf diesem Gerät")
        }
        if note.deletedAt != nil { return .placeholder("Notiz im Papierkorb") }
        guard let page = note.pages?.first(where: { $0.id == excerpt.pageID }) else {
            return .placeholder("Seite nicht gefunden")
        }
        guard let clipped = excerpt.clipped(toWidth: page.width, height: page.height) else {
            return .placeholder("Bereich liegt außerhalb der Seite")
        }
        let rect = CGRect(x: clipped.x, y: clipped.y, width: clipped.width, height: clipped.height)
        // Without the paper: an excerpt sits on the paper of the note that shows it. See ADR 0042.
        guard let image = PageImage.render(page, rect: rect, scale: scale, paper: nil, load: source.loadBlob) else {
            return .placeholder("Ausschnitt ließ sich nicht zeichnen")
        }
        return .image(image, size: rect.size)
    }
}

/// One excerpt in the text: a single attachment character that fits itself to the text width. See ADR 0032.
final class ExcerptAttachment: NSTextAttachment {
    /// Space above and below, so the card does not touch the neighbouring lines.
    static let margin: CGFloat = 6
    /// Text excerpts are set at this width and scaled down where the text is narrower.
    static let textWidth: Double = 560

    let target: ExcerptTarget
    let label: String
    /// Size of the card in points; never drawn larger.
    private let naturalSize: CGSize?

    @MainActor
    init(target: ExcerptTarget, label: String, source: ExcerptSource) {
        self.target = target
        self.label = label
        let card = ExcerptCards.card(for: target, caption: label, source: source, width: nil, height: nil)
        naturalSize = card.map { CGSize(width: $0.size.width, height: $0.size.height + Self.margin * 2) }
        super.init(data: nil, ofType: nil)
        if let card {
            image = Self.platformImage(card.image, size: card.size, margin: Self.margin)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint, characterIndex charIndex: Int
    ) -> CGRect {
        let available = max(lineFrag.width - NoteDocument.gutter, 40)
        guard let naturalSize, naturalSize.width > 0 else { return .zero }
        let width = min(naturalSize.width, available)
        let height = naturalSize.height * width / naturalSize.width
        // Below the baseline, so the line keeps no extra space under the card.
        return CGRect(x: 0, y: -Self.margin, width: width, height: height)
    }

    /// The card with free space above and below.
    private static func platformImage(_ image: CGImage, size: CGSize, margin: CGFloat) -> PlatformImage? {
        let scale = CGFloat(image.width) / max(size.width, 1)
        let pad = Int(margin * scale)
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height + pad * 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: pad, width: image.width, height: image.height))
        guard let padded = context.makeImage() else { return nil }
        let full = CGSize(width: size.width, height: size.height + margin * 2)
        #if os(macOS)
        return NSImage(cgImage: padded, size: full)
        #else
        return UIImage(cgImage: padded, scale: scale, orientation: .up)
        #endif
    }
}

/// Renders either kind of excerpt as a card: the content on the paper itself, a quiet rule on the left
/// like a quote, and where it comes from below. No box. Used in text and on pages. See ADR 0032 and 0037.
@MainActor
enum ExcerptCards {
    /// `width` nil keeps a page rectangle at its own size and sets text at `ExcerptAttachment.textWidth`.
    /// `height` nil lets text run to its end; otherwise it fades out.
    static func card(for target: ExcerptTarget, caption: String, source: ExcerptSource, width: Double?, height: Double?) -> (image: CGImage, size: CGSize)? {
        switch target {
        case let .page(excerpt):
            switch ExcerptRenderer.render(excerpt, source: source) {
            case let .image(image, size):
                let inner = width.map { max($0 - ExcerptCard.indent, 20) } ?? size.width
                let scaled = CGSize(width: inner, height: size.height * inner / max(size.width, 1))
                return render(ExcerptCard(ink: image, inkSize: scaled, caption: caption, note: nil))
            case let .placeholder(reason):
                return render(ExcerptCard(ink: nil, inkSize: CGSize(width: width ?? 320, height: 0), caption: caption, note: reason))
            }
        case let .text(excerpt):
            let content = textContent(excerpt, caption: caption, source: source)
            return render(TextExcerptCard(content: content, width: width ?? ExcerptAttachment.textWidth, height: height))
        }
    }

    static func textContent(_ excerpt: TextExcerpt, caption: String, source: ExcerptSource) -> TextExcerptCard.Content {
        guard let note = source.note(excerpt.noteID), note.deletedAt == nil, note.kind == .text else {
            return .missing("\(caption) · Textnotiz nicht auf diesem Gerät")
        }
        guard let blocks = MarkdownCodec.blocks(for: excerpt, in: note.markdown ?? "") else {
            return .missing("\(caption) · Die Stelle gibt es so nicht mehr")
        }
        return .text(blocks: blocks, caption: caption)
    }

    private static func render(_ view: some View) -> (image: CGImage, size: CGSize)? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return (image, CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
    }
}

struct ExcerptCard: View {
    /// Rule and gap before the content.
    static let indent: Double = 16.5

    var ink: CGImage?
    var inkSize: CGSize
    var caption: String
    var note: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Capsule()
                .fill(ink == nil ? Ink.muted.opacity(0.25) : Ink.accent.opacity(0.4))
                .frame(width: 2.5)
            VStack(alignment: .leading, spacing: 6) {
                if let ink {
                    Image(decorative: ink, scale: CGFloat(ink.width) / max(inkSize.width, 1))
                        .resizable()
                        .frame(width: inkSize.width, height: inkSize.height)
                }
                HStack(spacing: 5) {
                    Image(systemName: "scribble")
                    Text(caption).lineLimit(1)
                    if let note {
                        Text("· \(note)").lineLimit(1)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Ink.muted)
                .frame(width: ink == nil ? inkSize.width : nil, alignment: .leading)
            }
        }
        .fixedSize()
    }
}

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif
