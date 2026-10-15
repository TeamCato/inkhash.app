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
/// every device. See ADR 0042 and, for spacing and start, ADR 0047 and 0055.
enum PaperArt {
    private static let ink = CGColor(srgbRed: 0.11, green: 0.115, blue: 0.125, alpha: 1)

    /// Draws the pattern where it meets `visible`, a rectangle in page points. The context maps page
    /// points; `pixel` is one device pixel in page points, the thinnest a line may get.
    static func draw(_ paper: Paper, in context: CGContext, visible: CGRect, pageWidth: CGFloat, pixel: CGFloat) {
        let pattern = paper.pattern
        let spacing = CGFloat(paper.shownSpacing)
        guard spacing > 0, !visible.isEmpty else { return }
        let start = CGFloat(paper.shownStart)
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
        drawUnderInk(page, rect: rect, paper: paper, pixel: 1 / scale, in: context, load: load)
        context.restoreGState()

        // Ink on top, drawn upright in the unflipped bitmap.
        if let ink = inkImage(page, rect: rect, scale: scale, load: load) {
            context.draw(ink, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        return context.makeImage()
    }

    /// Paper and elements of `rect`, in page points with y down. Shared by bitmaps and PDF pages.
    static func drawUnderInk(_ page: InkPage, rect: CGRect, paper: Paper?, pixel: CGFloat, in context: CGContext, load: (String) -> Data?) {
        if let paper {
            context.setFillColor(paper.cgFill)
            context.fill(rect)
            PaperArt.draw(paper, in: context, visible: rect, pageWidth: page.width, pixel: pixel)
        }
        for element in page.elements.sorted(by: { $0.z < $1.z }) {
            context.saveGState()
            context.concatenate(ElementGeometry.transform(of: element))
            ElementRenderer.draw(element, in: context, image: ElementContent.image(for: element, load: load))
            context.restoreGState()
        }
    }

    /// The ink of `rect` as a bitmap, or nil for a page without a readable drawing.
    static func inkImage(_ page: InkPage, rect: CGRect, scale: CGFloat, load: (String) -> Data?) -> CGImage? {
        guard let data = load(page.blob), let drawing = try? PKDrawing(data: data) else { return nil }
        return cgImage(drawing.image(from: rect, scale: scale))
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
/// Where the page is narrower than the surface, it also draws the page's left and right edge (ADR 0057).
final class PaperPatternView: UIView {
    private var paper: Paper = .standard
    private var pageWidth: CGFloat = PageGeometry.width
    private var scale: CGFloat = 1
    private var edges = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// `visible` is the visible rectangle in content points of the canvas.
    func show(_ paper: Paper, visible: CGRect, pageWidth: CGFloat, scale: CGFloat, edges: Bool) {
        isHidden = paper.pattern == .blank && !edges
        guard paper != self.paper || visible != frame || pageWidth != self.pageWidth || scale != self.scale || edges != self.edges else { return }
        self.paper = paper
        self.pageWidth = pageWidth
        self.scale = scale
        self.edges = edges
        frame = visible
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard scale > 0, let context = UIGraphicsGetCurrentContext() else { return }
        if edges {
            // In view points, a hairline wide, where the page begins and ends.
            context.setFillColor(UIColor(Ink.hairline).cgColor)
            for x in [0, pageWidth * scale - 1] {
                context.fill(CGRect(x: x - frame.minX, y: rect.minY, width: 1, height: rect.height))
            }
        }
        guard paper.pattern != .blank else { return }
        // View points to content points to page points.
        context.translateBy(x: -frame.minX, y: -frame.minY)
        context.scaleBy(x: scale, y: scale)
        let visible = CGRect(
            x: (frame.minX + rect.minX) / scale, y: (frame.minY + rect.minY) / scale,
            width: rect.width / scale, height: rect.height / scale
        )
        PaperArt.draw(paper, in: context, visible: visible, pageWidth: pageWidth, pixel: 1 / (scale * contentScaleFactor))
    }
}
#endif

/// The whole pattern of a page, for the Mac's read-only page and for samples.
struct PaperPatternCanvas: View {
    var paper: Paper
    var pageWidth: Double
    /// Screen points per page point.
    var scale: CGFloat

    var body: some View {
        Canvas { context, size in
            guard paper.pattern != .blank, scale > 0 else { return }
            context.withCGContext { cg in
                cg.scaleBy(x: scale, y: scale)
                let visible = CGRect(x: 0, y: 0, width: size.width / scale, height: size.height / scale)
                PaperArt.draw(paper, in: cg, visible: visible, pageWidth: pageWidth, pixel: 0.5 / scale)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Colour and, for handwriting, pattern, spacing and start of a note. See ADR 0042, 0047 and 0055.
struct PaperPicker: View {
    var paper: Paper
    /// Text notes choose a colour only.
    var patterns: Bool
    var choose: (Paper) -> Void
    /// The paper while a slider moves, nil when it is let go. The page shows it so the pattern can
    /// be lined up with the writing; only `choose` changes the note.
    var preview: (Paper?) -> Void = { _ in }

    /// The paper while a slider moves. Only the end of a drag changes the note, so one drag is
    /// one change to save and sync, not one per step.
    @State private var draft: Paper?

    /// The paper as the picker shows it, a slider still being dragged included.
    private var shown: Paper { draft ?? paper }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Papier")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.muted)
            HStack(spacing: 10) {
                ForEach(Paper.palette, id: \.color) { entry in
                    let chosen = entry.color == paper.color
                    Button {
                        choose(paper.with(color: entry.color))
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
                        let sample = shown.with(pattern: pattern)
                        Button {
                            choose(paper.with(pattern: pattern))
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(paper.fill)
                                    .overlay(PaperPatternCanvas(paper: sample, pageWidth: 240, scale: 0.25))
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
                if paper.pattern != .blank {
                    slider(
                        "Abstand",
                        value: shown.shownSpacing,
                        isDefault: shown.spacing == nil,
                        range: Paper.spacingRange,
                        step: Paper.spacingStep,
                        reset: Paper(color: paper.color, pattern: paper.pattern, start: paper.start)
                    ) { Paper(color: paper.color, pattern: paper.pattern, spacing: $0, start: paper.start) }
                    slider(
                        "Erste Linie",
                        value: shown.shownStart,
                        isDefault: shown.start == nil,
                        range: Paper.startRange,
                        step: 1,
                        reset: Paper(color: paper.color, pattern: paper.pattern, spacing: paper.spacing)
                    ) { Paper(color: paper.color, pattern: paper.pattern, spacing: paper.spacing, start: $0) }
                }
            }
        }
        .padding(18)
        .presentationCompactAdaptation(.popover)
        .onDisappear {
            draft = nil
            preview(nil)
        }
    }

    /// One whole-point setting of the pattern. `make` builds the paper for a value; `reset` is the
    /// paper with that setting back at the pattern's default.
    private func slider(
        _ title: String,
        value: Int,
        isDefault: Bool,
        range: ClosedRange<Int>,
        step: Int,
        reset: Paper,
        make: @escaping (Int) -> Paper
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.muted)
                Spacer()
                if !isDefault {
                    Button("Standard") {
                        draft = nil
                        preview(nil)
                        choose(reset)
                    }
                    .font(.system(size: 13))
                    .buttonStyle(.plain)
                    .foregroundStyle(Ink.accent)
                }
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: {
                        let next = make(Int($0.rounded()))
                        draft = next
                        preview(next)
                    }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            ) {
                Text(title)
            } minimumValueLabel: {
                Image(systemName: "minus").foregroundStyle(Ink.muted)
            } maximumValueLabel: {
                Image(systemName: "plus").foregroundStyle(Ink.muted)
            } onEditingChanged: { editing in
                guard !editing, let next = draft else { return }
                choose(next)
                draft = nil
                preview(nil)
            }
            .tint(Ink.accent)
            .accessibilityValue("\(value) Punkte")
        }
    }
}
