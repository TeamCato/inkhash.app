import InkhashCore
import PencilKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import PhotosUI
import UIKit
#else
import AppKit
#endif

struct InkNoteView: View {
    @Environment(AppModel.self) private var model
    var note: Note
    @State private var readingPages: Set<UUID> = []
    @State private var recognitionGeneration: [UUID: Int] = [:]
    @State private var tools = InkToolState()
    @State private var editor = InkEditorState()
    @State private var pageIndex = 0
    @State private var compact = false
    #if os(iOS)
    @State private var photoItem: PhotosPickerItem?
    @State private var showsPhotos = false
    @State private var showsFiles = false
    @State private var showsTextExcerpt = false
    #endif

    init(note: Note) {
        self.note = note
    }

    /// The note as the model has it now. The `note` handed in is a copy from the parent's last render
    /// and lags behind our own edits when only this view updates.
    private var current: Note { model.record(note.id)?.note ?? note }

    var body: some View {
        let note = current
        let pages = note.pages ?? []
        let index = min(pageIndex, max(pages.count - 1, 0))
        VStack(spacing: 0) {
            NoteHeader(noteID: note.id)
                .zIndex(2)
                .padding(.leading, 20)
                .padding(.trailing, 20)
                .padding(.top, 12)
                .padding(.bottom, 6)
            HStack(spacing: 0) {
                #if os(iOS)
                // The tools sit at the edge, always open, never on the sheet. See ADR 0018 and 0028.
                if !compact {
                    InkToolRail(tools: tools, vertical: true, addImage: addImage)
                        .padding(.leading, 10)
                        .padding(.vertical, 10)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                #endif
                pageStack(pages, index: index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) { selectionBar(pages, index: index) }
            }
            #if os(iOS)
            if compact {
                InkToolRail(tools: tools, vertical: false, addImage: addImage)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            #endif
        }
        .compactWidth($compact)
        .background(Ink.paper.ignoresSafeArea())
        .overlay(alignment: .top) {
            if model.record(note.id)?.conflict == true {
                ConflictBanner(noteID: note.id)
                    .frame(maxWidth: 520)
                    .padding(.top, 12)
            }
        }
        .overlay(alignment: compact ? .topTrailing : .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                if !readingPages.isEmpty {
                    Text("lese Handschrift…")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.muted)
                }
                if !note.tags.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(note.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Ink.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .inkSurface(in: Capsule())
                        }
                    }
                }
            }
            .padding(16)
            .allowsHitTesting(false)
        }
        .toolbar {
            if pages.count > 1 {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { turn(to: max(0, pageIndex - 1)) } label: { Image(systemName: "chevron.up") }
                        .disabled(pageIndex == 0)
                        .accessibilityLabel("Vorige Seite")
                    Text("\(index + 1) / \(pages.count)")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.muted)
                    Button { turn(to: min(pages.count - 1, pageIndex + 1)) } label: { Image(systemName: "chevron.down") }
                        .disabled(pageIndex >= pages.count - 1)
                        .accessibilityLabel("Nächste Seite")
                }
            }
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.addPage(noteID: note.id, data: InkDrawing.empty())
                    turn(to: pages.count)
                } label: {
                    Image(systemName: "plus.rectangle.portrait")
                }
                .accessibilityLabel("Seite hinzufügen")
            }
            #endif
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showsPhotos, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { insertImage(data) }
                photoItem = nil
            }
        }
        .sheet(isPresented: $showsTextExcerpt) {
            ExcerptPicker(parent: current) { target, _ in
                showsTextExcerpt = false
                tools.choose(.select)
                editor.insertExcerpt(target)
            } cancel: {
                showsTextExcerpt = false
            }
            .environment(model)
        }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { insertImage(data) }
        }
        .onChange(of: tools.mode) { _, mode in
            if mode != .select { editor.clearSelection() }
        }
        #endif
        .onAppear {
            for page in pages {
                let data = model.drawingData(for: page.blob) ?? Data()
                guard page.transcript.isEmpty, !data.isEmpty, data != InkDrawing.empty() else { continue }
                recognize(page: page, data: data)
            }
        }
    }

    private func turn(to index: Int) {
        editor.clearSelection()
        pageIndex = index
    }

    #if os(iOS)
    private func addImage(_ source: ImageSource) {
        switch source {
        case .photos: showsPhotos = true
        case .files: showsFiles = true
        case .text: showsTextExcerpt = true
        }
    }

    private func insertImage(_ data: Data) {
        guard let stored = model.storeImage(data) else { return }
        tools.choose(.select)
        editor.insertImage(blob: stored.blob, size: stored.size)
    }
    #endif

    /// The selection with the margin of its outline, as an excerpt line on the pasteboard. See ADR 0032.
    private func copyExcerpt(page: InkPage) {
        guard let bounds = editor.selection?.bounds, !bounds.isNull else { return }
        let rect = bounds.insetBy(dx: -8, dy: -8)
        let x = max(rect.minX, 0)
        let y = max(rect.minY, 0)
        guard let excerpt = Excerpt(
            noteID: note.id, pageID: page.id, x: x, y: y,
            width: min(rect.maxX, page.width) - x, height: min(rect.maxY, page.height) - y
        ) else { return }
        let line = MarkdownCodec.serialize([MarkdownCodec.excerptBlock(excerpt, label: note.displayTitle)])
        #if os(iOS)
        UIPasteboard.general.string = line.trimmingCharacters(in: .newlines)
        #endif
        model.status = "Ausschnitt kopiert. In einer Textnotiz einfügen."
        editor.clearSelection()
    }

    @ViewBuilder
    private func selectionBar(_ pages: [InkPage], index: Int) -> some View {
        if editor.selection != nil || editor.maskDrawing != nil, pages.indices.contains(index) {
            let page = pages[index]
            let single = editor.selection.flatMap { selection in
                selection.elementIDs.count == 1 && !selection.hasInk
                    ? page.elements.first { $0.id == selection.elementIDs.first } : nil
            }
            InkSelectionBar(state: editor, element: single, excluding: note.id) {
                copyExcerpt(page: page)
            }
                .padding(.top, 10)
                .transition(.opacity)
        }
    }

    /// The current page fills the whole surface and is drawable everywhere. Its width fits the
    /// surface; it scrolls down and grows as the writing reaches the bottom. See ADR 0018.
    private func pageStack(_ pages: [InkPage], index: Int) -> some View {
        GeometryReader { geometry in
            if pages.indices.contains(index) {
                let page = pages[index]
                let scale = max(0.01, geometry.size.width / page.width)
                InkPageCanvas(
                    drawingData: model.drawingData(for: page.blob) ?? InkDrawing.empty(),
                    elements: page.elements,
                    pageID: page.id,
                    pageWidth: page.width,
                    pageHeight: page.height,
                    scale: scale,
                    // An iPhone has no pencil: the finger always draws, two fingers scroll. See ADR 0026.
                    fingerDrawing: tools.fingerDraws || Device.isPhone,
                    tools: tools,
                    editor: editor,
                    loadBlob: { model.drawingData(for: $0) },
                    onDrawing: { pageID, data, height in
                        // The page comes from the canvas that drew it, never from what is shown now.
                        // Only a changed drawing is read again; otherwise reading and reloading feed each other. See P-047.
                        guard model.updateDrawing(noteID: note.id, pageID: pageID, data: data, height: height) else { return }
                        if let drawn = model.record(note.id)?.note.pages?.first(where: { $0.id == pageID }) {
                            recognize(page: drawn, data: data)
                        }
                    },
                    onElements: { pageID, elements in
                        model.updateElements(noteID: note.id, pageID: pageID, elements: elements)
                    }
                )
                .id(page.id)
                .frame(width: geometry.size.width, height: geometry.size.height)
                #if os(iOS)
                .overlay(alignment: .topLeading) {
                    PageBadges(elements: page.elements, scale: scale)
                        .offset(x: -editor.offset.x, y: -editor.offset.y)
                }
                .clipped()
                #endif
            }
        }
    }

    /// Reads a page after a short pause in writing. Every stroke asks again; only the newest request
    /// may write its result, so a slow early reading cannot overwrite a later one. See P-043.
    private func recognize(page: InkPage, data: Data) {
        let noteID = note.id
        let pageID = page.id
        let width = page.width
        let height = page.height
        let generation = (recognitionGeneration[pageID] ?? 0) + 1
        recognitionGeneration[pageID] = generation
        readingPages.insert(pageID)
        Task {
            // The newest request for the page clears the mark, however it ends.
            defer { if recognitionGeneration[pageID] == generation { readingPages.remove(pageID) } }
            try? await Task.sleep(for: .milliseconds(900))
            guard recognitionGeneration[pageID] == generation else { return }
            let drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
            let reading = await HandwritingRecognizer.recognize(drawing: drawing, width: width, height: height)
            guard recognitionGeneration[pageID] == generation else { return }
            if drawing.strokes.isEmpty {
                model.applyReading(noteID: noteID, pageID: pageID, transcript: "", tags: [], pageHasInk: false)
            } else {
                model.applyReading(noteID: noteID, pageID: pageID, transcript: reading.transcript, tags: reading.tags, pageHasInk: true)
            }
        }
    }
}

/// Link marks at the top-right corner of every linked element, in screen points from the page origin.
struct PageBadges: View {
    var elements: [PageElement]
    var scale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: 1, height: 1)
            ForEach(elements.filter { $0.link != nil }) { element in
                let point = ElementGeometry.badgePoint(of: element)
                LinkBadge(target: element.link ?? "")
                    .offset(x: point.x * scale - 18, y: point.y * scale - 18)
            }
        }
    }
}

#if os(iOS)
struct InkPageCanvas: UIViewRepresentable {
    var drawingData: Data
    var elements: [PageElement]
    var pageID: UUID
    var pageWidth: Double
    var pageHeight: Double
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
            canvas.bringSubviewToFront(overlay)
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

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
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
                if bottom > 0, bottom > height - InkPageCanvas.growMargin {
                    height = min(InkPageCanvas.maxHeight, bottom + InkPageCanvas.growStep)
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

        private var nextZ: Int { (elements.map(\.z).max() ?? 0) + 1 }

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
            selectedIDs = Set(elements.filter { rect.contains(CGPoint(x: $0.x, y: $0.y)) }.map(\.id))
            selectedStrokes = []
            if let canvas {
                for (index, stroke) in canvas.drawing.strokes.enumerated() {
                    let bounds = stroke.renderBounds
                    if rect.contains(CGPoint(x: bounds.midX, y: bounds.midY)) { selectedStrokes.append(index) }
                }
            }
            refreshSelection()
        }

        func deleteSelection() {
            guard let canvas else { return }
            let remaining = elements.filter { !selectedIDs.contains($0.id) }
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
            var next = elements
            if !selectedStrokes.isEmpty, let target {
                // Ink cannot carry a link; an invisible area over it does.
                let area = selectionBounds.insetBy(dx: -12, dy: -12)
                let link = PageElement(kind: .link, x: area.midX, y: area.midY, width: area.width, height: area.height, z: nextZ, link: target)
                next.append(link)
                selectedIDs = [link.id]
                selectedStrokes = []
            } else if target == nil {
                // An area that only existed for its link goes with it.
                next.removeAll { selectedIDs.contains($0.id) && $0.kind == .link }
                for index in next.indices where selectedIDs.contains(next[index].id) { next[index].link = nil }
            } else {
                for index in next.indices where selectedIDs.contains(next[index].id) { next[index].link = target }
            }
            commit(elements: next, name: "Link")
        }

        func changeSelected(_ body: @escaping (inout PageElement) -> Void) {
            var next = elements
            for index in next.indices where selectedIDs.contains(next[index].id) { body(&next[index]) }
            commit(elements: next, name: "Ändern")
        }

        func restack(front: Bool) {
            var next = elements
            let target = front ? nextZ : (elements.map(\.z).min() ?? 0) - 1
            for index in next.indices where selectedIDs.contains(next[index].id) { next[index].z = target }
            commit(elements: next, name: front ? "Nach vorn" : "Nach hinten")
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
            let longest = min(480, parent.pageWidth - 80)
            let ratio = longest / max(pixelSize.width, pixelSize.height, 1)
            let image = PageElement(
                kind: .image, x: center.x, y: center.y,
                width: max(40, pixelSize.width * ratio), height: max(40, pixelSize.height * ratio),
                rotation: Double.random(in: -0.03...0.03), z: nextZ, blob: blob, frame: .classic
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
                follow(resizeTransform(anchor: anchor, start: start, point: point))
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
                finishTransform(cancelled ? .identity : resizeTransform(anchor: anchor, start: start, point: point), name: "Größe")
            case nil:
                break
            }
        }

        private func resizeTransform(anchor: CGPoint, start: CGPoint, point: CGPoint) -> CGAffineTransform {
            let from = max(hypot(start.x - anchor.x, start.y - anchor.y), 1)
            let to = hypot(point.x - anchor.x, point.y - anchor.y)
            let factor = min(max(to / from, 0.1), 10)
            return CGAffineTransform(translationX: anchor.x, y: anchor.y).scaledBy(x: factor, y: factor).translatedBy(x: -anchor.x, y: -anchor.y)
        }

        /// While dragging: element views and the lifted ink follow; the model does not change yet.
        private func follow(_ transform: CGAffineTransform) {
            for element in dragElements where selectedIDs.contains(element.id) {
                elementViews[element.id]?.update(Self.transformed(element, by: transform), image: ElementContent.image(for: element, load: parent.loadBlob))
            }
            if !snapshot.isHidden {
                snapshot.transform = .identity
                let frame = snapshot.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let moved = center.applying(transform)
                let factor = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
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
            let next = dragElements.map { selectedIDs.contains($0.id) ? Self.transformed($0, by: transform) : $0 }
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

        static func transformed(_ element: PageElement, by transform: CGAffineTransform) -> PageElement {
            var copy = element
            let center = CGPoint(x: element.x, y: element.y).applying(transform)
            let factor = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
            copy.x = center.x
            copy.y = center.y
            copy.width = max(8, element.width * factor)
            copy.height = max(8, element.height * factor)
            return copy
        }

        private func createShape(from start: CGPoint, to end: CGPoint) {
            let form = parent.tools.shapeForm
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 4 else { return }
            let shape: PageElement
            if form == .line {
                // A line is a flat box along the drag, turned; the box is its hit area.
                shape = parent.tools.shapeElement(
                    form: .line, x: (start.x + end.x) / 2, y: (start.y + end.y) / 2,
                    width: length, height: max(parent.tools.shapeWidth, 24),
                    rotation: atan2(end.y - start.y, end.x - start.x), z: nextZ
                )
            } else {
                let rect = CGRect(start: start, end: end)
                guard rect.width > 4, rect.height > 4 else { return }
                shape = parent.tools.shapeElement(form: form, x: rect.midX, y: rect.midY, width: rect.width, height: rect.height, rotation: 0, z: nextZ)
            }
            commit(elements: elements + [shape], name: "Form")
        }

        private func tapePath(from start: CGPoint, to end: CGPoint) -> CGPath {
            let tape = tapeElement(from: start, to: end)
            let path = CGMutablePath()
            path.addRect(CGRect(x: 0, y: 0, width: tape.width, height: tape.height), transform: ElementGeometry.transform(of: tape))
            return path
        }

        private func tapeElement(from start: CGPoint, to end: CGPoint) -> PageElement {
            var length = hypot(end.x - start.x, end.y - start.y)
            var angle = atan2(end.y - start.y, end.x - start.x)
            var center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            if length < 20 {
                // A short touch puts down a strip of the usual length, slightly askew.
                length = 240
                angle = 0.08
                center = start
            }
            return PageElement(
                kind: .tape, x: center.x, y: center.y, width: length, height: parent.tools.tapeWidth,
                rotation: angle, z: nextZ, color: parent.tools.tapeColor
            )
        }

        private func createTape(from start: CGPoint, to end: CGPoint) {
            commit(elements: elements + [tapeElement(from: start, to: end)], name: "Tape")
        }

        /// Turns the drawn outline into a freehand mask, 0…1 in the photo area of the image.
        private func finishMask(_ points: [CGPoint]) {
            guard let id = maskTarget, let element = elements.first(where: { $0.id == id }), points.count > 2 else { return }
            let content = ElementRenderer.contentRect(in: CGRect(x: 0, y: 0, width: element.width, height: element.height), frame: element.frame)
            let inverse = ElementGeometry.transform(of: element).inverted()
            let normalized = points.map { point -> PageElement.Point in
                let local = point.applying(inverse)
                return PageElement.Point(
                    x: min(max((local.x - content.minX) / max(content.width, 1), 0), 1),
                    y: min(max((local.y - content.minY) / max(content.height, 1), 0), 1)
                )
            }
            maskTarget = nil
            parent.editor.maskDrawing = nil
            applyMode()
            var next = elements
            if let index = next.firstIndex(where: { $0.id == id }) {
                next[index].mask = PageElement.Mask(kind: .freehand, points: Self.thinned(normalized))
            }
            commit(elements: next, name: "Maske")
        }

        /// At most 400 points, so the outline stays within what the server takes.
        static func thinned(_ points: [PageElement.Point]) -> [PageElement.Point] {
            guard points.count > 400 else { return points }
            let step = Double(points.count) / 400
            return (0..<400).map { points[Int(Double($0) * step)] }
        }
    }
}

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

#else
/// macOS PencilKit can read and render a PKDrawing, but it has no canvas view.
/// Handwriting is written on the iPad. The Mac shows the page, its elements and their links.
struct InkPageCanvas: View {
    var drawingData: Data
    var elements: [PageElement]
    var pageID: UUID
    var pageWidth: Double
    var pageHeight: Double
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
