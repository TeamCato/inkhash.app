#if os(iOS)
import InkhashCore
import SwiftUI
import UIKit

/// One element under the ink. Draws itself with the shared renderer.
final class ElementView: UIView {
    private var element: PageElement?
    private var image: CGImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ next: PageElement, image nextImage: CGImage?) {
        let changed = next.kind != element?.kind || next.width != element?.width || next.height != element?.height
            || next.frame != element?.frame || next.mask != element?.mask || next.color != element?.color
            || next.stroke != element?.stroke || next.strokeWidth != element?.strokeWidth || next.fill != element?.fill
            || next.fillOpacity != element?.fillOpacity || next.shape != element?.shape || nextImage !== image
        element = next
        image = nextImage
        // Room around the box for a frame's shadow; drawing starts at the box origin.
        let margin: CGFloat = next.kind == .image ? 16 : 2
        transform = .identity
        bounds = CGRect(x: -margin, y: -margin, width: next.width + margin * 2, height: next.height + margin * 2)
        center = CGPoint(x: next.x, y: next.y)
        transform = CGAffineTransform(rotationAngle: next.rotation)
        if next.kind == .link {
            // A link area shows itself softly in the editor so it can be found.
            backgroundColor = UIColor(Ink.accent).withAlphaComponent(0.07)
            layer.cornerRadius = 8
        } else {
            backgroundColor = .clear
        }
        if changed { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let element, let context = UIGraphicsGetCurrentContext() else { return }
        ElementRenderer.draw(element, in: context, image: image)
    }
}

/// Lets touches through unless they land on a subview that wants them.
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

extension CGRect {
    init(start: CGPoint, end: CGPoint) {
        self.init(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}
#endif
