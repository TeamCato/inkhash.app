import CoreGraphics
import ImageIO
import InkhashCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Draws page elements with Core Graphics, the same on iPad, iPhone and Mac. See ADR 0028.
enum ElementRenderer {
    /// Draws `element` into `context`, whose origin is the element's top-left corner, unrotated.
    static func draw(_ element: PageElement, in context: CGContext, image: CGImage?) {
        let box = CGRect(x: 0, y: 0, width: element.width, height: element.height)
        context.saveGState()
        defer { context.restoreGState() }
        switch element.kind {
        case .image:
            drawImage(element, box: box, in: context, image: image)
        case .shape:
            drawShape(element, box: box, in: context)
        case .tape:
            let base = cgColor(element.color ?? Self.defaultTape)
            context.setFillColor(base.copy(alpha: 0.62) ?? base)
            context.fill(box)
            context.setStrokeColor(base.copy(alpha: 0.9) ?? base)
            context.setLineWidth(1)
            context.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        case .link:
            break
        case .excerpt:
            // The card is rendered at the element's size; drawn upright in the y-down context.
            guard let image else { return }
            context.translateBy(x: 0, y: box.maxY + box.minY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: box)
        }
    }

    static let defaultTape = "#F0E6C7"

    /// The photo area inside a frame. Polaroid leaves a deeper bottom edge. Same geometry as Scweble.
    static func contentRect(in box: CGRect, frame: PageElement.Frame?) -> CGRect {
        ElementGeometry.contentRect(in: box, frame: frame)
    }

    static func maskPath(_ mask: PageElement.Mask, in rect: CGRect) -> CGPath {
        switch mask.kind {
        case .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .freehand:
            guard let first = mask.points.first else { return CGPath(rect: rect, transform: nil) }
            let path = CGMutablePath()
            func map(_ point: PageElement.Point) -> CGPoint {
                CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
            }
            path.move(to: map(first))
            for point in mask.points.dropFirst() { path.addLine(to: map(point)) }
            path.closeSubpath()
            return path
        }
    }

    private static func drawImage(_ element: PageElement, box: CGRect, in context: CGContext, image: CGImage?) {
        let frame = element.frame
        let content = contentRect(in: box, frame: frame)
        let hasFrame = frame.map { $0.style != .none && $0.width > 0 } ?? false
        let outline: CGPath = {
            if !hasFrame, let mask = element.mask { return maskPath(mask, in: content) }
            return CGPath(rect: hasFrame ? box : content, transform: nil)
        }()
        if frame?.shadow ?? false {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: 4), blur: 10, color: CGColor(gray: 0, alpha: 0.25))
            context.addPath(outline)
            context.setFillColor(hasFrame ? cgColor(frame?.color ?? "#FFFFFF") : CGColor(gray: 0.9, alpha: 1))
            context.fillPath()
            context.restoreGState()
        } else if hasFrame {
            context.addPath(outline)
            context.setFillColor(cgColor(frame?.color ?? "#FFFFFF"))
            context.fillPath()
        }
        context.saveGState()
        context.addPath(element.mask.map { maskPath($0, in: content) } ?? CGPath(rect: content, transform: nil))
        context.clip()
        if let image {
            // Aspect fill, centred.
            let ratio = max(content.width / CGFloat(image.width), content.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
            let target = CGRect(x: content.midX - size.width / 2, y: content.midY - size.height / 2, width: size.width, height: size.height)
            // Core Graphics draws images with y up; the context is y down.
            context.translateBy(x: 0, y: target.maxY + target.minY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: target)
        } else {
            context.setFillColor(CGColor(gray: 0.9, alpha: 1))
            context.fill(content)
        }
        context.restoreGState()
    }

    static func shapePath(_ form: PageElement.ShapeForm, in box: CGRect) -> CGPath {
        switch form {
        case .line:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: box.minX, y: box.midY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.midY))
            return path
        case .rect:
            return CGPath(rect: box, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: box, transform: nil)
        case .triangle:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: box.midX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
            path.closeSubpath()
            return path
        }
    }

    private static func drawShape(_ element: PageElement, box: CGRect, in context: CGContext) {
        let width = CGFloat(element.strokeWidth ?? 3)
        let form = element.shape ?? .rect
        // The contour sits inside the box, so a selected shape does not grow by half a stroke.
        let inner = form == .line ? box : box.insetBy(dx: width / 2, dy: width / 2)
        let path = shapePath(form, in: inner)
        if let fill = element.fill, form != .line {
            context.addPath(path)
            context.setFillColor(cgColor(fill).copy(alpha: CGFloat(element.fillOpacity ?? 1)) ?? cgColor(fill))
            context.fillPath()
        }
        if let stroke = element.stroke {
            context.addPath(path)
            context.setStrokeColor(cgColor(stroke))
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        }
    }

    static func cgColor(_ hex: String) -> CGColor {
        var value: UInt64 = 0
        Scanner(string: String(hex.drop(while: { $0 == "#" }))).scanHexInt64(&value)
        return CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Decoded photos by blob, shared by all pages. Decoding a JPEG for every redraw would stall scrolling.
@MainActor
final class ElementImages {
    static let shared = ElementImages()
    private var cache: [String: CGImage] = [:]

    func image(for blob: String?, load: (String) -> Data?) -> CGImage? {
        guard let blob else { return nil }
        if let cached = cache[blob] { return cached }
        guard let data = load(blob),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        if cache.count > 64 { cache.removeAll() }
        cache[blob] = image
        return image
    }
}

/// Photos become JPEG, at most 2000 pixels on the long side, like in Scweble. See ADR 0028.
enum ImageImport {
    static let maxPixels: CGFloat = 2000

    static func jpeg(from data: Data) -> (data: Data, size: CGSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (output as Data, CGSize(width: image.width, height: image.height))
    }
}

/// Renders the elements of a page as one image, for the Mac and for snapshots.
enum PageElementsImage {
    @MainActor
    static func cgImage(elements: [PageElement], size: CGSize, scale: CGFloat, load: (String) -> Data?) -> CGImage? {
        guard !elements.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // y down, page points.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        for element in elements.sorted(by: { $0.z < $1.z }) {
            context.saveGState()
            context.concatenate(ElementGeometry.transform(of: element))
            ElementRenderer.draw(element, in: context, image: ElementContent.image(for: element, load: load))
            context.restoreGState()
        }
        return context.makeImage()
    }
}

/// The small link mark on an element. A tap follows the link, in every tool. See ADR 0028.
struct LinkBadge: View {
    @Environment(AppModel.self) private var model
    var target: String

    var body: some View {
        Button {
            model.openLink(target)
        } label: {
            Image(systemName: NoteLink.noteID(in: target) == nil ? "arrow.up.right" : "doc.text")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Ink.paper)
                .frame(width: 24, height: 24)
                .background(Ink.accent, in: Circle())
                .overlay(Circle().strokeBorder(Ink.paper, lineWidth: 2))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(target)
        .accessibilityLabel("Link öffnen")
    }
}
