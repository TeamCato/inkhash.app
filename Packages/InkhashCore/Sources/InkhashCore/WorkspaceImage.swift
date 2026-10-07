import CoreGraphics
import Foundation
import ImageIO

public enum WorkspaceImageError: Error, Equatable {
    case unreadable
    case unwritable
}

/// Turns any picture into the square PNG a workspace shows as its icon. See ADR 0043.
public enum WorkspaceImage {
    /// Edge length in pixels. Enough for the largest place an icon shows, at 3x.
    public static let side = 192

    /// Crops the middle square, scales it to `side` and encodes it as PNG.
    /// Honors the orientation stored in photos.
    public static func normalize(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw WorkspaceImageError.unreadable }
        // The thumbnail applies the orientation and keeps decoding cheap for large photos.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 4,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WorkspaceImageError.unreadable
        }
        let edge = min(image.width, image.height)
        let crop = CGRect(x: (image.width - edge) / 2, y: (image.height - edge) / 2, width: edge, height: edge)
        guard edge > 0, let square = image.cropping(to: crop) else { throw WorkspaceImageError.unreadable }

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw WorkspaceImageError.unwritable }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let scaled = context.makeImage() else { throw WorkspaceImageError.unwritable }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw WorkspaceImageError.unwritable
        }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { throw WorkspaceImageError.unwritable }
        return output as Data
    }
}
