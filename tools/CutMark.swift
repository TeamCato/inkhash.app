import AppKit
import CoreImage

// Cuts the painted # out of the app icon artwork: paper becomes transparent, brush and splashes stay.
// Run via `make icon`.
//
//   cut-mark <AppIconArtwork.png> <mark.png>
//
// The plate edges of the artwork belong to the icon, not to the mark; everything
// outside a centred circle fades out. See ADR 0066, 0080 and 0088.

/// Radius of the circle that keeps the #, as a share of the artwork's side. The bar ends reach almost to it.
let keepRadius = 0.48
/// Width of the soft edge of that circle, as a share of the side.
let keepFeather = 0.04
let outputSize = 512

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
}

/// RGBA pixels of an image as floats in 0…1, row by row from the top.
func pixels(of image: CGImage, width: Int, height: Int) -> [Float] {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { fail("cannot create a drawing context", 70) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return bytes.map { Float($0) / 255 }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: cut-mark <AppIconArtwork.png> <mark.png>", 64) }
guard
    let artwork = NSImage(contentsOfFile: arguments[1])?
        .cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fail("cannot read \(arguments[1])", 66) }
let width = artwork.width
let height = artwork.height
guard width == height else { fail("expected a square artwork, got \(width)×\(height)", 65) }

// The paper behind each pixel: the brightest colour nearby, smoothed so the brush itself drops out.
let source = CIImage(cgImage: artwork)
let paperImage =
    source
    .clampedToExtent()
    .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 30])
    .applyingGaussianBlur(sigma: 60)
    .cropped(to: source.extent)
guard let paperCG = CIContext().createCGImage(paperImage, from: source.extent) else {
    fail("cannot find the paper", 70)
}
let rgb = pixels(of: artwork, width: width, height: height)
let paper = pixels(of: paperCG, width: width, height: height)

var mark = [UInt8](repeating: 0, count: width * height * 4)
var minX = width
var minY = height
var maxX = -1
var maxY = -1
let centre = Double(width) / 2
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        // How much darker than its paper a pixel is. Light grain stays below the knee and becomes transparent.
        var darkness: Float = 0
        for c in 0..<3 {
            darkness = max(darkness, 1 - rgb[i + c] / max(paper[i + c], 1e-3))
        }
        let knee = min(max((darkness - 0.13) / 0.25, 0), 1)
        let distance = ((Double(x) - centre) * (Double(x) - centre) + (Double(y) - centre) * (Double(y) - centre))
            .squareRoot() / Double(width)
        let keep = Float(min(max((keepRadius + keepFeather - distance) / keepFeather, 0), 1))
        let alpha = min(darkness * 1.05, 1) * knee * knee * (3 - 2 * knee) * keep
        guard alpha > 0 else { continue }
        // The colour that, laid over the paper with that alpha, gives the painted pixel back.
        // Stored premultiplied, as the bitmap context below expects.
        for c in 0..<3 {
            let colour = min(max((rgb[i + c] - (1 - alpha) * paper[i + c]) / max(alpha, 1e-3), 0), 1)
            mark[i + c] = UInt8((colour * alpha * 255).rounded())
        }
        mark[i + 3] = UInt8((alpha * 255).rounded())
        if alpha > 0.3 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }
}
guard maxX >= minX else { fail("no brush strokes found in \(arguments[1])", 65) }

guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
    let markProvider = CGDataProvider(data: Data(mark) as CFData),
    let markImage = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: markProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
else { fail("cannot assemble the mark", 70) }

// Square around the strokes, centred, with a little air.
let side = max(maxX - minX + 1, maxY - minY + 1) + 24
let left = (minX + maxX + 1 - side) / 2
let top = (minY + maxY + 1 - side) / 2
guard
    let output = CGContext(
        data: nil, width: outputSize, height: outputSize, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fail("cannot create the output context", 70) }
output.interpolationQuality = .high
let scale = CGFloat(outputSize) / CGFloat(side)
// Core Graphics counts rows from the bottom; place the full artwork so the square lands on the output.
output.draw(
    markImage,
    in: CGRect(
        x: -CGFloat(left) * scale, y: -CGFloat(height - top - side) * scale,
        width: CGFloat(width) * scale, height: CGFloat(height) * scale))

guard let result = output.makeImage(),
    let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])
else { fail("cannot encode the mark", 70) }
do {
    try png.write(to: URL(fileURLWithPath: arguments[2]))
} catch {
    fail("cannot write \(arguments[2]): \(error.localizedDescription)", 73)
}
