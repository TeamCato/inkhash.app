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
    @State private var showsPaper = false
    @State private var showsPages = false
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
    private var current: Note { model.library.record(note.id)?.note ?? note }

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
        // The paper's colour is the whole screen of the note, also under the title. See ADR 0042.
        .background(note.shownPaper.fill.ignoresSafeArea())
        .overlay(alignment: .top) {
            if model.library.record(note.id)?.conflict == true {
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
                    Button { showsPages = true } label: { Image(systemName: "square.grid.2x2") }
                        .accessibilityLabel("Seiten ordnen")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showsPaper = true } label: { Image(systemName: "rectangle.split.3x3") }
                    .accessibilityLabel("Papier")
                    .popover(isPresented: $showsPaper) {
                        PaperPicker(paper: note.shownPaper, patterns: true) { model.library.setPaper(noteID: note.id, paper: $0) }
                    }
            }
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.library.addPage(noteID: note.id, data: InkDrawing.empty())
                    turn(to: pages.count)
                } label: {
                    Image(systemName: "plus.rectangle.portrait")
                }
                .accessibilityLabel("Seite hinzufügen")
            }
            #endif
        }
        .navigationTitle("")
        .sheet(isPresented: $showsPages) {
            PageOverview(noteID: note.id, current: pages.indices.contains(index) ? pages[index].id : nil) { pageID in
                if let target = current.pages?.firstIndex(where: { $0.id == pageID }) { turn(to: target) }
            }
            .environment(model)
        }
        // Moving or deleting pages keeps the open page open, or the one that took its place.
        .onChange(of: pages.map(\.id)) { old, new in
            guard old.indices.contains(pageIndex) else { return }
            if let moved = new.firstIndex(of: old[pageIndex]) {
                if moved != pageIndex { turn(to: moved) }
            } else {
                turn(to: min(pageIndex, max(new.count - 1, 0)))
            }
        }
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
                let data = model.library.drawingData(for: page.blob) ?? Data()
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
        guard let stored = model.library.storeImage(data) else { return }
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
                    drawingData: model.library.drawingData(for: page.blob) ?? InkDrawing.empty(),
                    elements: page.elements,
                    pageID: page.id,
                    pageWidth: page.width,
                    pageHeight: page.height,
                    paper: current.shownPaper,
                    scale: scale,
                    // An iPhone has no pencil: the finger always draws, two fingers scroll. See ADR 0026.
                    fingerDrawing: tools.fingerDraws || Device.isPhone,
                    tools: tools,
                    editor: editor,
                    loadBlob: { model.library.drawingData(for: $0) },
                    onDrawing: { pageID, data, height in
                        // The page comes from the canvas that drew it, never from what is shown now.
                        // Only a changed drawing is read again; otherwise reading and reloading feed each other. See P-047.
                        guard model.library.updateDrawing(noteID: note.id, pageID: pageID, data: data, height: height) else { return }
                        if let drawn = model.library.record(note.id)?.note.pages?.first(where: { $0.id == pageID }) {
                            recognize(page: drawn, data: data)
                        }
                    },
                    onElements: { pageID, elements in
                        model.library.updateElements(noteID: note.id, pageID: pageID, elements: elements)
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
                model.library.applyReading(noteID: noteID, pageID: pageID, transcript: "", tags: [], pageHasInk: false)
            } else {
                model.library.applyReading(noteID: noteID, pageID: pageID, transcript: reading.transcript, tags: reading.tags, pageHasInk: true)
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
