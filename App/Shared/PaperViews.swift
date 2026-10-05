import InkhashCore
import PencilKit
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Paper {
    /// The colour to fill the note with; a malformed colour falls back to the standard paper.
    var fill: Color {
        guard let rgb = components else { return Ink.paper }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    var cgFill: CGColor {
        let rgb = components ?? Paper.standard.components ?? (1, 1, 1)
        return CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}

/// Lines, grid and dots, drawn in page points so they sit at the same place of the writing on
/// every device. See ADR 0042.
enum PaperArt {
    private static let ink = CGColor(srgbRed: 0.11, green: 0.115, blue: 0.125, alpha: 1)

    /// Draws the pattern where it meets `visible`, a rectangle in page points. The context maps page
    /// points; `pixel` is one device pixel in page points, the thinnest a line may get.
    static func draw(_ pattern: PaperPattern, in context: CGContext, visible: CGRect, pageWidth: CGFloat, pixel: CGFloat) {
        let spacing = CGFloat(pattern.spacing)
        guard spacing > 0, !visible.isEmpty else { return }
        let start = CGFloat(pattern.start)
        let firstRow = max(0, Int(((visible.minY - start) / spacing).rounded(.down)))
        let lastRow = Int(((visible.maxY - start) / spacing).rounded(.up))
        guard lastRow >= firstRow else { return }
        let rows = (firstRow...lastRow).map { start + CGFloat($0) * spacing }
        let columns = stride(from: spacing, to: pageWidth, by: spacing).filter {
            $0 >= visible.minX - spacing && $0 <= visible.maxX + spacing
        }
        context.saveGState()
        defer { context.restoreGState() }
        switch pattern {
        case .blank:
            return
        case .lines, .grid:
            context.setStrokeColor(ink.copy(alpha: pattern == .lines ? 0.16 : 0.10) ?? ink)
            context.setLineWidth(max(0.6, pixel))
            for y in rows {
                context.move(to: CGPoint(x: max(0, visible.minX), y: y))
                context.addLine(to: CGPoint(x: min(pageWidth, visible.maxX), y: y))
            }
            if pattern == .grid {
                for x in columns {
                    context.move(to: CGPoint(x: x, y: visible.minY))
                    context.addLine(to: CGPoint(x: x, y: visible.maxY))
                }
            }
            context.strokePath()
        case .dots:
            context.setFillColor(ink.copy(alpha: 0.32) ?? ink)
            let radius = max(1.2, pixel)
            for y in rows {
                for x in columns {
                    context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
            }
        }
    }
}

/// A rectangle of a page as a bitmap: paper if given, elements under the ink, as on the page.
@MainActor
enum PageImage {
    static func render(_ page: InkPage, rect: CGRect, scale: CGFloat, paper: Paper?, load: (String) -> Data?) -> CGImage? {
        let pixelWidth = max(Int(rect.width * scale), 1)
        let pixelHeight = max(Int(rect.height * scale), 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Page points, y down, shifted so the rectangle starts at the origin.
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        if let paper {
            context.setFillColor(paper.cgFill)
            context.fill(rect)
            PaperArt.draw(paper.pattern, in: context, visible: rect, pageWidth: page.width, pixel: 1 / scale)
        }
        for element in page.elements.sorted(by: { $0.z < $1.z }) {
            context.saveGState()
            context.concatenate(ElementGeometry.transform(of: element))
            ElementRenderer.draw(element, in: context, image: ElementContent.image(for: element, load: load))
            context.restoreGState()
        }
        context.restoreGState()

        // Ink on top, drawn upright in the unflipped bitmap.
        if let data = load(page.blob), let drawing = try? PKDrawing(data: data),
           let ink = cgImage(drawing.image(from: rect, scale: scale)) {
            context.draw(ink, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        return context.makeImage()
    }

    #if os(macOS)
    private static func cgImage(_ image: NSImage) -> CGImage? {
        var proposed = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }
    #else
    private static func cgImage(_ image: UIImage) -> CGImage? {
        image.cgImage
    }
    #endif
}

#if os(iOS)
/// The pattern under the visible part of a page. It covers only what is on screen and follows the
/// scrolling: a view over a whole 10 000 point page would hold a bitmap far too large. See ADR 0042.
final class PaperPatternView: UIView {
    private var pattern: PaperPattern = .blank
    private var pageWidth: CGFloat = PageGeometry.width
    private var scale: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// `visible` is the visible rectangle in content points of the canvas.
    func show(_ pattern: PaperPattern, visible: CGRect, pageWidth: CGFloat, scale: CGFloat) {
        isHidden = pattern == .blank
        guard pattern != self.pattern || visible != frame || pageWidth != self.pageWidth || scale != self.scale else { return }
        self.pattern = pattern
        self.pageWidth = pageWidth
        self.scale = scale
        frame = visible
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard pattern != .blank, scale > 0, let context = UIGraphicsGetCurrentContext() else { return }
        // View points to content points to page points.
        context.translateBy(x: -frame.minX, y: -frame.minY)
        context.scaleBy(x: scale, y: scale)
        let visible = CGRect(
            x: (frame.minX + rect.minX) / scale, y: (frame.minY + rect.minY) / scale,
            width: rect.width / scale, height: rect.height / scale
        )
        PaperArt.draw(pattern, in: context, visible: visible, pageWidth: pageWidth, pixel: 1 / (scale * contentScaleFactor))
    }
}
#endif

/// The whole pattern of a page, for the Mac's read-only page and for samples.
struct PaperPatternCanvas: View {
    var pattern: PaperPattern
    var pageWidth: Double
    /// Screen points per page point.
    var scale: CGFloat

    var body: some View {
        Canvas { context, size in
            guard pattern != .blank, scale > 0 else { return }
            context.withCGContext { cg in
                cg.scaleBy(x: scale, y: scale)
                let visible = CGRect(x: 0, y: 0, width: size.width / scale, height: size.height / scale)
                PaperArt.draw(pattern, in: cg, visible: visible, pageWidth: pageWidth, pixel: 0.5 / scale)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Colour and, for handwriting, pattern of a note. See ADR 0042.
struct PaperPicker: View {
    var paper: Paper
    /// Text notes choose a colour only.
    var patterns: Bool
    var choose: (Paper) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Papier")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.muted)
            HStack(spacing: 10) {
                ForEach(Paper.palette, id: \.color) { entry in
                    let chosen = entry.color == paper.color
                    Button {
                        choose(Paper(color: entry.color, pattern: paper.pattern))
                    } label: {
                        Circle()
                            .fill(Paper(color: entry.color).fill)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Ink.ink.opacity(0.14), lineWidth: 1))
                            .padding(3)
                            .overlay(Circle().strokeBorder(chosen ? Ink.accent : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.name)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            if patterns {
                HStack(spacing: 10) {
                    ForEach(PaperPattern.allCases, id: \.self) { pattern in
                        let chosen = pattern == paper.pattern
                        Button {
                            choose(Paper(color: paper.color, pattern: pattern))
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(paper.fill)
                                    .overlay(PaperPatternCanvas(pattern: pattern, pageWidth: 240, scale: 0.25))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(chosen ? Ink.accent : Ink.ink.opacity(0.14), lineWidth: chosen ? 2 : 1)
                                    )
                                    .frame(width: 54, height: 70)
                                Text(pattern.label)
                                    .font(.system(size: 12))
                                    .foregroundStyle(chosen ? Ink.ink : Ink.muted)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pattern.label)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
        }
        .padding(18)
        .presentationCompactAdaptation(.popover)
    }
}
