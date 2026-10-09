import InkhashCore
import PencilKit
import SwiftUI

#if os(iOS)
import UIKit

struct InkPageCanvas: UIViewRepresentable {
    var drawingData: Data
    var elements: [PageElement]
    var pageID: UUID
    var pageWidth: Double
    var pageHeight: Double
    /// Lines, grid or dots under everything, see ADR 0042. The colour is the view's background.
    var paper: Paper
    /// Screen points per page point. Strokes and elements stay in page coordinates, see ADR 0018.
    var scale: CGFloat
    var fingerDrawing: Bool
    var tools: InkToolState
    var editor: InkEditorState
    var loadBlob: (String) -> Data?
    /// The page that was drawn on, its drawing and the page height it needs.
    var onDrawing: (UUID, Data, Double) -> Void
    var onElements: (UUID, [PageElement]) -> Void

    /// Room kept below the lowest stroke, in page points. Writing into it grows the page.
    static let growMargin: Double = 320
    static let growStep: Double = 640
    static let maxHeight: Double = 10_000

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        let coordinator = context.coordinator
        canvas.delegate = coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = true
        canvas.alwaysBounceVertical = true
        canvas.showsVerticalScrollIndicator = true
        canvas.contentInsetAdjustmentBehavior = .never
        coordinator.canvas = canvas
        coordinator.pageID = pageID
        coordinator.height = pageHeight
        coordinator.install(in: canvas)
        canvas.tool = coordinator.parentTool()
        applyZoom(canvas, coordinator: coordinator)
        coordinator.appliedTool = tools.strokeTool
        coordinator.load(drawingData)
        coordinator.syncElements(elements, force: true)
        coordinator.applyMode()
        coordinator.redrawSoon()
        editor.controller = coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.pageID != pageID {
            // Another page in the same view: what was drawn belongs to the old one.
            coordinator.flush()
            coordinator.pageID = pageID
            coordinator.height = pageHeight
            coordinator.localHash = nil
        }
        coordinator.parent = self
        editor.controller = coordinator
        applyZoom(canvas, coordinator: coordinator)
        coordinator.applyMode()
        coordinator.applyToolIfIdle()
        coordinator.sync(drawingData)
        coordinator.syncElements(elements, force: false)
    }

    /// Width fits the surface. The content is at least as tall as the surface, so every spot is drawable.
    private func applyZoom(_ canvas: PKCanvasView, coordinator: Coordinator) {
        guard scale > 0 else { return }
        if abs(canvas.zoomScale - scale) > 0.001 {
            canvas.minimumZoomScale = scale
            canvas.maximumZoomScale = scale
            canvas.zoomScale = scale
            coordinator.redrawSoon()
        }
        Self.layoutContent(canvas, pageWidth: pageWidth, pageHeight: pageHeight, scale: scale)
        coordinator.layoutLayers()
    }

    static func layoutContent(_ canvas: PKCanvasView, pageWidth: Double, pageHeight: Double, scale: CGFloat) {
        let visible = canvas.bounds.height / max(scale, 0.01)
        let height = max(pageHeight, Double(visible))
        let size = CGSize(width: pageWidth * scale, height: height * scale)
        if canvas.contentSize != size { canvas.contentSize = size }
    }

    fileprivate var policy: PKCanvasViewDrawingPolicy {
        #if targetEnvironment(simulator)
        .anyInput
        #else
        fingerDrawing ? .anyInput : .pencilOnly
        #endif
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.flush()
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate, InkPageControlling {
        var parent: InkPageCanvas
        weak var canvas: PKCanvasView?
        var localHash: String?
        var usingTool = false
        var appliedTool: InkStrokeTool?
        var saveItem: DispatchWorkItem?
        var height: Double = PageGeometry.height
        /// The page this canvas holds. Saves always go to it, see P-034.
        var pageID: UUID?
        private var pending: Data?

        /// Elements live under the ink, the overlay above it. Both use page coordinates, scaled.
        /// The paper's pattern lies under the elements and covers only the visible rectangle.
        private let paperView = PaperPatternView()
        private let elementLayer = PassthroughView()
        private let overlay = PassthroughView()
        private var elementViews: [UUID: ElementView] = [:]
        private(set) var elements: [PageElement] = []
        private let preview = CAShapeLayer()
        private let selectionOutline = CAShapeLayer()
        private let snapshot = UIImageView()
        private var pan: UIPanGestureRecognizer?
        private var tap: UITapGestureRecognizer?

        private var selectedIDs: Set<UUID> = []
        private var selectedStrokes: [Int] = []
        private var selectionBounds: CGRect = .null
        private var maskTarget: UUID?

        private enum Drag {
            case marquee(CGPoint)
            case move(CGPoint)
            case resize(anchor: CGPoint, start: CGPoint)
            case shape(CGPoint)
            case tape(CGPoint)
            case mask([CGPoint])
        }

        private var drag: Drag?
        private var dragStrokes: [PKStroke] = []
        private var dragElements: [PageElement] = []

        init(parent: InkPageCanvas) {
            self.parent = parent
        }

        // MARK: Setup

        func install(in canvas: PKCanvasView) {
            elementLayer.layer.anchorPoint = .zero
            overlay.layer.anchorPoint = .zero
            canvas.insertSubview(elementLayer, at: 0)
            canvas.insertSubview(paperView, at: 0)
            canvas.addSubview(overlay)
            for layer in [preview, selectionOutline] {
                layer.fillColor = UIColor(Ink.accent).withAlphaComponent(0.06).cgColor
                layer.strokeColor = UIColor(Ink.accent).withAlphaComponent(0.7).cgColor
                layer.lineDashPattern = [6, 5]
                overlay.layer.addSublayer(layer)
            }
            selectionOutline.fillColor = UIColor.clear.cgColor
            snapshot.isHidden = true
            overlay.addSubview(snapshot)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            canvas.addGestureRecognizer(pan)
            self.pan = pan
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.delegate = self
            canvas.addGestureRecognizer(tap)
            self.tap = tap
        }

        func layoutLayers() {
            guard let canvas else { return }
            let scale = max(parent.scale, 0.01)
            let pageHeight = max(height, parent.pageHeight, Double(canvas.bounds.height / scale))
            for layer in [elementLayer, overlay] {
                layer.transform = .identity
                layer.bounds = CGRect(x: 0, y: 0, width: parent.pageWidth, height: pageHeight)
                layer.layer.position = .zero
                layer.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
            let pixels = canvas.traitCollection.displayScale * scale
            for view in elementViews.values where view.contentScaleFactor != pixels {
                view.contentScaleFactor = pixels
            }
            canvas.sendSubviewToBack(elementLayer)
            canvas.sendSubviewToBack(paperView)
            canvas.bringSubviewToFront(overlay)
            layoutPaper()
            // SwiftUI can update before the canvas has its final size; place the pattern again once it has.
            DispatchQueue.main.async { [weak self] in self?.layoutPaper() }
            preview.lineWidth = 1.5 / scale
            selectionOutline.lineWidth = 1.5 / scale
        }

        /// Which touches go where, by tool. Drawing tools give the page to PencilKit; the others to us.
        func applyMode() {
            guard let canvas else { return }
            let mode = parent.tools.mode
            let ours = mode != .draw || maskTarget != nil
            canvas.drawingGestureRecognizer.isEnabled = !ours
            canvas.drawingPolicy = ours ? .pencilOnly : parent.policy
            // When one finger draws or frames, scrolling takes two.
            let twoFingers = ours || parent.policy == .anyInput
            if canvas.panGestureRecognizer.minimumNumberOfTouches != (twoFingers ? 2 : 1) {
                canvas.panGestureRecognizer.minimumNumberOfTouches = twoFingers ? 2 : 1
            }
            pan?.isEnabled = ours
            tap?.isEnabled = mode == .select && maskTarget == nil
            if mode != .select, !selectedIDs.isEmpty || !selectedStrokes.isEmpty { select(nil) }
        }

        // MARK: Drawing

        /// PencilKit does not paint strokes it got before the canvas had its size and zoom.
        /// Handing the same drawing over again once layout is done makes them appear, see P-034.
        func redrawSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let canvas = self.canvas, !self.usingTool, !canvas.drawing.strokes.isEmpty else { return }
                let drawing = canvas.drawing
                canvas.drawing = PKDrawing()
                canvas.drawing = drawing
            }
        }

        /// Saves a drawing that is still waiting for its delay, to the page it was drawn on.
        func flush() {
            saveItem?.cancel()
            saveItem = nil
            guard let data = pending else { return }
            publish(data)
        }

        func load(_ data: Data) {
            guard let canvas else { return }
            // Loading is no drawing: it must not save and read the page again. See P-047.
            settingDrawing = true
            canvas.drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
            settingDrawing = false
            localHash = sha256Hex(canvas.drawing.dataRepresentation())
        }

        func sync(_ data: Data) {
            guard !usingTool, drag == nil else { return }
            let hash = sha256Hex(data)
            if hash == localHash { return }
            load(data)
            selectedStrokes = []
        }

        /// The pattern follows the visible rectangle, in content points of the canvas.
        func layoutPaper() {
            guard let canvas else { return }
            paperView.show(parent.paper, visible: canvas.bounds, pageWidth: parent.pageWidth, scale: parent.scale)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            layoutPaper()
            let offset = scrollView.contentOffset
            if parent.editor.offset != offset { parent.editor.offset = offset }
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            usingTool = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            usingTool = false
            saveItem?.cancel()
            publish(canvasView.drawing.dataRepresentation())
            applyToolIfIdle()
        }

        func parentTool() -> PKTool {
            let tool = parent.tools.strokeTool
            if tool.erasing {
                return tool.pixelErase ? PKEraserTool(.bitmap, width: tool.width) : PKEraserTool(.vector)
            }
            return PKInkingTool(tool.pen.inkType, color: UIColor(inkHex: tool.colorHex), width: tool.width)
        }

        func applyToolIfIdle() {
            guard !usingTool, appliedTool != parent.tools.strokeTool, let canvas else { return }
            canvas.tool = parentTool()
            appliedTool = parent.tools.strokeTool
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard drag == nil, !settingDrawing else { return }
            selectedStrokes = []
            saveItem?.cancel()
            pending = canvasView.drawing.dataRepresentation()
            let item = DispatchWorkItem { [weak self] in
                guard let self, let data = self.pending else { return }
                self.publish(data)
            }
            saveItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
        }

        private var settingDrawing = false

        func publish(_ data: Data) {
            pending = nil
            guard let pageID else { return }
            localHash = sha256Hex(data)
            height = max(height, parent.pageHeight)
            if let canvas {
                let bottom = max(
                    canvas.drawing.strokes.isEmpty ? 0 : Double(canvas.drawing.bounds.maxY),
                    elements.map { Double(ElementGeometry.bounds(of: $0).maxY) }.max() ?? 0
                )
                let grown = PageEdits.grownHeight(
                    current: height, contentBottom: bottom,
                    margin: InkPageCanvas.growMargin, step: InkPageCanvas.growStep, limit: InkPageCanvas.maxHeight
                )
                if grown != height {
                    height = grown
                    InkPageCanvas.layoutContent(canvas, pageWidth: parent.pageWidth, pageHeight: height, scale: parent.scale)
                    layoutLayers()
                }
            }
            parent.onDrawing(pageID, data, height)
        }

        // MARK: Elements

        func syncElements(_ next: [PageElement], force: Bool) {
            if !force {
                guard drag == nil, next != elements else {
                    if next == elements { beforeCommit = nil }
                    return
                }
                // What we had before our own last change, coming back late from SwiftUI: not news.
                if let beforeCommit, next == beforeCommit { return }
            }
            beforeCommit = nil
            elements = next
            render()
        }

        private var beforeCommit: [PageElement]?

        private func render() {
            let ids = Set(elements.map(\.id))
            for (id, view) in elementViews where !ids.contains(id) {
                view.removeFromSuperview()
                elementViews[id] = nil
            }
            let pixels = (canvas?.traitCollection.displayScale ?? 2) * max(parent.scale, 0.01)
            for element in elements.sorted(by: { $0.z < $1.z }) {
                let view: ElementView
                if let existing = elementViews[element.id] {
                    view = existing
                } else {
                    view = ElementView()
                    elementViews[element.id] = view
                    elementLayer.addSubview(view)
                }
                if view.contentScaleFactor != pixels { view.contentScaleFactor = pixels }
                view.update(element, image: ElementContent.image(for: element, load: parent.loadBlob))
                elementLayer.bringSubviewToFront(view)
            }
            refreshSelection()
        }

        /// Saves the elements, with one undo step back to what was there before.
        private func commit(elements next: [PageElement], drawing: PKDrawing? = nil, name: String) {
            guard let pageID, let canvas else { return }
            let previousElements = elements
            let previousDrawing = drawing == nil ? nil : canvas.drawing
            beforeCommit = previousElements
            elements = next
            render()
            parent.onElements(pageID, next)
            if let drawing {
                settingDrawing = true
                canvas.drawing = drawing
                settingDrawing = false
                saveItem?.cancel()
                publish(drawing.dataRepresentation())
            }
            canvas.undoManager?.registerUndo(withTarget: self) { coordinator in
                MainActor.assumeIsolated {
                    coordinator.commit(elements: previousElements, drawing: previousDrawing, name: name)
                }
            }
            canvas.undoManager?.setActionName(name)
        }

        private var nextZ: Int { PageEdits.topZ(elements) }

        // MARK: Selection

        func select(_ ids: Set<UUID>?) {
            selectedIDs = ids ?? []
            selectedStrokes = []
            refreshSelection()
        }

        private func refreshSelection() {
            selectedIDs = selectedIDs.filter { id in elements.contains { $0.id == id } }
            var bounds = CGRect.null
            for element in elements where selectedIDs.contains(element.id) {
                bounds = bounds.union(ElementGeometry.bounds(of: element))
            }
            if let canvas {
                for index in selectedStrokes where canvas.drawing.strokes.indices.contains(index) {
                    bounds = bounds.union(canvas.drawing.strokes[index].renderBounds)
                }
            }
            selectionBounds = bounds
            if bounds.isNull {
                selectionOutline.path = nil
                if parent.editor.selection != nil { parent.editor.selection = nil }
                return
            }
            let outline = UIBezierPath(roundedRect: bounds.insetBy(dx: -8, dy: -8), cornerRadius: 6)
            outline.append(UIBezierPath(ovalIn: handleRect(bounds)))
            selectionOutline.path = outline.cgPath
            let next = InkEditorState.Selection(elementIDs: selectedIDs, strokeCount: selectedStrokes.count, bounds: bounds)
            if parent.editor.selection != next { parent.editor.selection = next }
        }

        private func handleRect(_ bounds: CGRect) -> CGRect {
            let side = 14 / max(parent.scale, 0.01)
            return CGRect(x: bounds.maxX + 8 - side / 2, y: bounds.maxY + 8 - side / 2, width: side, height: side)
        }

        /// Elements by their center, strokes by the center of their bounds. Same rule as Scweble.
        private func selectContent(in rect: CGRect) {
            let strokes = canvas?.drawing.strokes.map(\.renderBounds) ?? []
            (selectedIDs, selectedStrokes) = PageEdits.selection(in: rect, elements: elements, strokeBounds: strokes)
            refreshSelection()
        }

        func deleteSelection() {
            guard let canvas else { return }
            let remaining = PageEdits.removing(selectedIDs, from: elements)
            var drawing: PKDrawing?
            if !selectedStrokes.isEmpty {
                let removed = Set(selectedStrokes)
                drawing = PKDrawing(strokes: canvas.drawing.strokes.enumerated().filter { !removed.contains($0.offset) }.map(\.element))
            }
            selectedIDs = []
            selectedStrokes = []
            commit(elements: remaining, drawing: drawing, name: "Löschen")
        }

        func setLink(_ target: String?) {
            let result = PageEdits.linking(
                selectedIDs, in: elements, to: target,
                strokeBounds: selectedStrokes.isEmpty ? nil : selectionBounds
            )
            if target != nil, !selectedStrokes.isEmpty { selectedStrokes = [] }
            selectedIDs = result.selected
            commit(elements: result.elements, name: "Link")
        }

        func changeSelected(_ body: @escaping (inout PageElement) -> Void) {
            var next = elements
            for index in next.indices where selectedIDs.contains(next[index].id) { body(&next[index]) }
            commit(elements: next, name: "Ändern")
        }

        func restack(front: Bool) {
            commit(elements: PageEdits.restacking(selectedIDs, in: elements, front: front), name: front ? "Nach vorn" : "Nach hinten")
        }

        func setMaskDrawing(_ id: UUID?) {
            maskTarget = id
            applyMode()
        }

        func insertImage(blob: String, pixelSize: CGSize) {
            guard let canvas else { return }
            let scale = max(parent.scale, 0.01)
            let visible = CGRect(origin: canvas.contentOffset, size: canvas.bounds.size)
            let center = CGPoint(x: visible.midX / scale, y: visible.midY / scale)
            let image = PageEdits.image(
                blob: blob, pixelSize: pixelSize, center: center, pageWidth: parent.pageWidth,
                z: nextZ, rotation: Double.random(in: -0.03...0.03)
            )
            selectedIDs = [image.id]
            selectedStrokes = []
            commit(elements: elements + [image], name: "Bild")
        }

        func insertExcerpt(_ target: ExcerptTarget) {
            guard let canvas else { return }
            let scale = max(parent.scale, 0.01)
            let visible = CGRect(origin: canvas.contentOffset, size: canvas.bounds.size)
            let center = (x: Double(visible.midX / scale), y: Double(visible.midY / scale))
            let width: Double = {
                if case let .page(page) = target { return min(page.width, 420) + ExcerptCard.indent }
                return 380
            }()
            let height = ExcerptElementImages.shared.naturalHeight(of: target, width: width)
            var excerpt = PageElement.excerpt(target, center: center, width: width, height: max(height, 40))
            excerpt.z = nextZ
            selectedIDs = [excerpt.id]
            selectedStrokes = []
            commit(elements: elements + [excerpt], name: "Ausschnitt")
        }

        // MARK: Gestures

        /// PencilKit's own taps (its edit menu, "Insert Space") wait for ours while a page tool is active.
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard gesture === tap || gesture === pan, let canvas, other.view === canvas else { return false }
            return other !== canvas.panGestureRecognizer && other !== canvas.pinchGestureRecognizer && other !== pan && other !== tap
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: elementLayer)
            if !selectionBounds.isNull, selectionBounds.insetBy(dx: -8, dy: -8).contains(point), selectedIDs.count + selectedStrokes.count > 1 {
                return
            }
            if let hit = ElementGeometry.element(at: point, in: elements) {
                select([hit.id])
            } else {
                select(nil)
            }
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: elementLayer)
            switch gesture.state {
            case .began:
                // Start where the finger went down, not where the pan was recognised.
                let translation = gesture.translation(in: elementLayer)
                beginDrag(at: CGPoint(x: point.x - translation.x, y: point.y - translation.y))
                continueDrag(to: point)
            case .changed:
                continueDrag(to: point)
            case .ended:
                endDrag(at: point, cancelled: false)
            case .cancelled, .failed:
                endDrag(at: point, cancelled: true)
            default:
                break
            }
        }

        private func beginDrag(at point: CGPoint) {
            if maskTarget != nil {
                drag = .mask([point])
                return
            }
            switch parent.tools.mode {
            case .draw:
                drag = nil
            case .shape:
                drag = .shape(point)
            case .tape:
                drag = .tape(point)
            case .select:
                if !selectionBounds.isNull, handleRect(selectionBounds).insetBy(dx: -12, dy: -12).contains(point) {
                    drag = .resize(anchor: selectionBounds.origin, start: point)
                } else if !selectionBounds.isNull, selectionBounds.insetBy(dx: -8, dy: -8).contains(point) {
                    drag = .move(point)
                } else if let hit = ElementGeometry.element(at: point, in: elements) {
                    select([hit.id])
                    drag = .move(point)
                } else {
                    select(nil)
                    drag = .marquee(point)
                }
                if case .marquee = drag {} else { liftSelection() }
            }
        }

        /// Takes the selected strokes off the canvas into a picture that follows the finger.
        private func liftSelection() {
            guard let canvas else { return }
            dragElements = elements
            dragStrokes = canvas.drawing.strokes
            guard !selectedStrokes.isEmpty else { return }
            let chosen = Set(selectedStrokes)
            let lifted = PKDrawing(strokes: dragStrokes.enumerated().filter { chosen.contains($0.offset) }.map(\.element))
            let rect = lifted.bounds.insetBy(dx: -4, dy: -4)
            snapshot.transform = .identity
            snapshot.image = lifted.image(from: rect, scale: canvas.traitCollection.displayScale * parent.scale)
            snapshot.frame = rect
            snapshot.isHidden = false
            settingDrawing = true
            canvas.drawing = PKDrawing(strokes: dragStrokes.enumerated().filter { !chosen.contains($0.offset) }.map(\.element))
            settingDrawing = false
        }

        private func continueDrag(to point: CGPoint) {
            switch drag {
            case .marquee(let start):
                preview.path = UIBezierPath(rect: CGRect(start: start, end: point)).cgPath
            case .shape(let start):
                let form = parent.tools.shapeForm
                if form == .line {
                    let path = UIBezierPath()
                    path.move(to: start)
                    path.addLine(to: point)
                    preview.path = path.cgPath
                } else {
                    preview.path = ElementRenderer.shapePath(form, in: CGRect(start: start, end: point))
                }
            case .tape(let start):
                preview.path = tapePath(from: start, to: point)
            case .mask(var points):
                points.append(point)
                drag = .mask(points)
                let path = UIBezierPath()
                path.move(to: points[0])
                for next in points.dropFirst() { path.addLine(to: next) }
                preview.path = path.cgPath
            case .move(let start):
                follow(CGAffineTransform(translationX: point.x - start.x, y: point.y - start.y))
            case .resize(let anchor, let start):
                follow(PageEdits.resizeTransform(anchor: anchor, start: start, point: point))
            case nil:
                break
            }
        }

        private func endDrag(at point: CGPoint, cancelled: Bool) {
            let current = drag
            drag = nil
            preview.path = nil
            switch current {
            case .marquee(let start):
                let rect = CGRect(start: start, end: point)
                if rect.width > 4 || rect.height > 4 { selectContent(in: rect) }
            case .shape(let start):
                if !cancelled { createShape(from: start, to: point) }
            case .tape(let start):
                if !cancelled { createTape(from: start, to: point) }
            case .mask(let points):
                if !cancelled { finishMask(points) }
            case .move(let start):
                finishTransform(cancelled ? .identity : CGAffineTransform(translationX: point.x - start.x, y: point.y - start.y), name: "Verschieben")
            case .resize(let anchor, let start):
                finishTransform(cancelled ? .identity : PageEdits.resizeTransform(anchor: anchor, start: start, point: point), name: "Größe")
            case nil:
                break
            }
        }

        /// While dragging: element views and the lifted ink follow; the model does not change yet.
        private func follow(_ transform: CGAffineTransform) {
            for element in dragElements where selectedIDs.contains(element.id) {
                elementViews[element.id]?.update(PageEdits.transformed(element, by: transform), image: ElementContent.image(for: element, load: parent.loadBlob))
            }
            if !snapshot.isHidden {
                snapshot.transform = .identity
                let frame = snapshot.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let moved = center.applying(transform)
                let factor = PageEdits.scale(of: transform)
                snapshot.transform = CGAffineTransform(translationX: moved.x - center.x, y: moved.y - center.y).scaledBy(x: factor, y: factor)
            }
            let outline = selectionBounds.applying(transform)
            selectionOutline.path = UIBezierPath(roundedRect: outline.insetBy(dx: -8, dy: -8), cornerRadius: 6).cgPath
        }

        private func finishTransform(_ transform: CGAffineTransform, name: String) {
            guard let canvas else { return }
            snapshot.isHidden = true
            snapshot.transform = .identity
            snapshot.image = nil
            let next = PageEdits.transforming(selectedIDs, in: dragElements, by: transform)
            var drawing: PKDrawing?
            if !selectedStrokes.isEmpty {
                let chosen = Set(selectedStrokes)
                var strokes = dragStrokes
                for index in strokes.indices where chosen.contains(index) {
                    strokes[index].transform = strokes[index].transform.concatenating(transform)
                }
                drawing = PKDrawing(strokes: strokes)
            }
            dragStrokes = []
            dragElements = []
            if transform == .identity {
                if let drawing {
                    settingDrawing = true
                    canvas.drawing = drawing
                    settingDrawing = false
                }
                render()
                return
            }
            commit(elements: next, drawing: drawing, name: name)
        }

        private func createShape(from start: CGPoint, to end: CGPoint) {
            let form = parent.tools.shapeForm
            guard let box = PageEdits.shapeBox(form, from: start, to: end, lineThickness: parent.tools.shapeWidth) else { return }
            let shape = parent.tools.shapeElement(
                form: form, x: box.x, y: box.y, width: box.width, height: box.height, rotation: box.rotation, z: nextZ
            )
            commit(elements: elements + [shape], name: "Form")
        }

        private func tapePath(from start: CGPoint, to end: CGPoint) -> CGPath {
            let tape = tapeElement(from: start, to: end)
            let path = CGMutablePath()
            path.addRect(CGRect(x: 0, y: 0, width: tape.width, height: tape.height), transform: ElementGeometry.transform(of: tape))
            return path
        }

        private func tapeElement(from start: CGPoint, to end: CGPoint) -> PageElement {
            PageEdits.tape(from: start, to: end, width: parent.tools.tapeWidth, color: parent.tools.tapeColor, z: nextZ)
        }

        private func createTape(from start: CGPoint, to end: CGPoint) {
            commit(elements: elements + [tapeElement(from: start, to: end)], name: "Tape")
        }

        /// Turns the drawn outline into a freehand mask, 0…1 in the photo area of the image.
        private func finishMask(_ points: [CGPoint]) {
            guard let id = maskTarget, let element = elements.first(where: { $0.id == id }),
                  let mask = PageEdits.mask(from: points, on: element) else { return }
            maskTarget = nil
            parent.editor.maskDrawing = nil
            applyMode()
            var next = elements
            if let index = next.firstIndex(where: { $0.id == id }) {
                next[index].mask = mask
            }
            commit(elements: next, name: "Maske")
        }
    }
}
#else
/// macOS PencilKit can read and render a PKDrawing, but it has no canvas view.
/// Handwriting is written on the iPad. The Mac shows the page, its elements and their links.
struct InkPageCanvas: View {
    var drawingData: Data
    var elements: [PageElement]
    var pageID: UUID
    var pageWidth: Double
    var pageHeight: Double
    var paper: Paper
    var scale: CGFloat
    var fingerDrawing: Bool
    var tools: InkToolState
    var editor: InkEditorState
    var loadBlob: (String) -> Data?
    var onDrawing: (UUID, Data, Double) -> Void
    var onElements: (UUID, [PageElement]) -> Void

    var body: some View {
        let drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        let size = CGSize(width: pageWidth, height: pageHeight)
        ScrollView(.vertical) {
            ZStack(alignment: .topLeading) {
                PaperPatternCanvas(paper: paper, pageWidth: pageWidth, scale: scale)
                    .frame(width: pageWidth * scale, height: pageHeight * scale)
                if let image = PageElementsImage.cgImage(elements: elements, size: size, scale: 2, load: loadBlob) {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: pageWidth * scale, height: pageHeight * scale)
                }
                Image(nsImage: drawing.image(from: CGRect(origin: .zero, size: size), scale: 2))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: pageWidth * scale, height: pageHeight * scale)
                    .accessibilityLabel("Handschrift")
                PageBadges(elements: elements, scale: scale)
            }
            .frame(width: pageWidth * scale, height: pageHeight * scale, alignment: .topLeading)
        }
    }
}
#endif
