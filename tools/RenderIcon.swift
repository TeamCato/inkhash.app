import AppKit
import SwiftUI

// Renders the app icon from InkhashMark in App/Shared/Theme.swift, so the icon
// and the in-app mark share one drawing. Run via `make icon`.
//
//   render-icon <AppIcon.png>              iOS: full square, the system rounds the corners
//   render-icon --mac <appiconset folder>  macOS: rounded plate on Apple's grid, every size
//
// macOS does not mask icons. A full-bleed square is shown as a foreign icon: shrunk onto a
// grey plate since macOS 26. The Mac icon therefore carries its own shape.

private let paper = Color(red: 0.976, green: 0.973, blue: 0.965)

struct IconFace: View {
    var body: some View {
        ZStack {
            paper
            InkhashMark()
                .frame(width: 600, height: 600)
                .offset(x: 6)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// Apple's macOS grid on 1024: an 824 plate centred, corner radius 185, a soft shadow below.
struct MacIconFace: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(paper)
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
            InkhashMark()
                .frame(width: 600 * 824 / 1024, height: 600 * 824 / 1024)
                .offset(x: 6 * 824 / 1024)
        }
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
