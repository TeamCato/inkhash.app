import InkhashCore
import SwiftUI

/// A workspace's own picture, or its symbol when it has none. See ADR 0043.
struct WorkspaceIcon: View {
    @Environment(AppModel.self) private var model
    var workspace: Workspace
    var size: CGFloat = 18

    var body: some View {
        if let image = model.registry.image(of: workspace) {
            WorkspacePicture(image: image, size: size)
        } else {
            Image(systemName: workspace.symbol)
        }
    }
}

struct WorkspacePicture: View {
    var image: PlatformImage
    var size: CGFloat

    var body: some View {
        Image(platformImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

/// A workspace entry for a `Menu`. Menus ignore frames and clip shapes on images,
/// so the picture is drawn at menu size with its corners already rounded.
struct WorkspaceMenuLabel: View {
    @Environment(AppModel.self) private var model
    var workspace: Workspace
    /// The current workspace shows a checkmark instead of its icon.
    var isCurrent = false

    var body: some View {
        Label {
            Text(workspace.name)
            // Where it lies, while Kennel is connected (teamCato ADR 0009 point 1); encrypted ones say so (ADR 0082).
            if model.kennel != nil {
                Text(model.overview.place(of: workspace).label + (workspace.link?.sealed == true ? " · verschlüsselt" : ""))
            }
        } icon: {
            if isCurrent {
                Image(systemName: "checkmark")
            } else if let image = model.registry.image(of: workspace) {
                Image(platformImage: image.menuIcon(side: 18))
            } else {
                Image(systemName: workspace.symbol)
            }
        }
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension PlatformImage {
    /// A square copy `side` points wide with rounded corners, drawn in its own colors.
    func menuIcon(side: CGFloat) -> PlatformImage {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let radius = side * 0.25
        #if os(macOS)
        return NSImage(size: rect.size, flipped: false) { bounds in
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
            self.draw(in: bounds)
            return true
        }
        #else
        return UIGraphicsImageRenderer(size: rect.size).image { _ in
            UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
            draw(in: rect)
        }
        .withRenderingMode(.alwaysOriginal)
        #endif
    }
}
