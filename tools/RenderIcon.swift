import AppKit
import SwiftUI

// Lays out the painted app icon (tools/AppIconArtwork.png) for iOS and macOS. Run via `make icon`.
//
//   render-icon <AppIcon.png>              iOS: full square, the system rounds the corners
//   render-icon --mac <appiconset folder>  macOS: rounded plate on Apple's grid, every size
//
// macOS does not mask icons. A full-bleed square is shown as a foreign icon: shrunk onto a
// grey plate since macOS 26. The Mac icon therefore carries its own shape.

/// The painted icon: brush strokes and paper from Dominik's icon sheet (ADR 0066), 1024 square.
/// Brush grain and paper cannot be drawn by hand in code, so the artwork is a file, and this tool
/// only lays it out for each platform. The in-app mark `InkhashMark` follows its strokes.
@MainActor private let artwork: NSImage = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("AppIconArtwork.png")
    guard let image = NSImage(contentsOf: url) else { fatalError("missing \(url.path)") }
    return image
}()

struct IconFace: View {
    var body: some View {
        Image(nsImage: artwork)
            .resizable()
            .frame(width: 1024, height: 1024)
    }
}

/// Apple's macOS grid on 1024: an 824 plate centred, corner radius 185, a soft shadow below.
struct MacIconFace: View {
    var body: some View {
        Image(nsImage: artwork)
            .resizable()
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
            .frame(width: 1024, height: 1024)
    }
}

@main
struct RenderIcon {
    /// Points and scales of a macOS app icon set.
    static let macSizes: [(points: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }

    @MainActor
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--mac" {
            let folder = URL(fileURLWithPath: arguments.dropFirst().first ?? ".")
            for size in macSizes {
                let pixels = size.points * size.scale
                let name = "AppIcon-mac-\(size.points)\(size.scale == 2 ? "@2x" : "").png"
                try write(MacIconFace(), scale: CGFloat(pixels) / 1024, to: folder.appendingPathComponent(name))
            }
        } else {
            try write(IconFace(), scale: 1, to: URL(fileURLWithPath: arguments.first ?? "AppIcon.png"))
        }
    }

    @MainActor
    static func write(_ view: some View, scale: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = false
        guard let image = renderer.cgImage else {
            throw NSError(domain: "RenderIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "rendering failed"])
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "RenderIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
        }
        try png.write(to: url)
    }
}
