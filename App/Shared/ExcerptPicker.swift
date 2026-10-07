import InkhashCore
import PencilKit
import SwiftUI

/// Picks what an excerpt shows: a rectangle of a handwriting page or paragraphs of a text note, from
/// any note of the workspace, or a new note written right here. New notes go into a folder named after
/// the note they are made from, with an automatic title. See ADR 0032, 0035 and 0037.
struct ExcerptPicker: View {
    @Environment(AppModel.self) private var model
    /// The note the excerpt goes into. It is not offered: a note does not show itself.
    var parent: Note
    var insert: (_ target: ExcerptTarget, _ label: String) -> Void
    var cancel: () -> Void

    private enum Step: Equatable {
        case list
        case page(UUID)
        case text(UUID)
        case writing(UUID)
    }

    @State private var query = ""
    @State private var step = Step.list
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            Group {
                switch step {
                case .list:
                    noteList
                case let .page(id):
                    if let note = model.library.record(id)?.note {
                        PageAreaPicker(note: note) { excerpt in insert(.page(excerpt), note.displayTitle) }
                    }
                case let .text(id):
                    if let note = model.library.record(id)?.note {
                        TextRangePicker(note: note) { excerpt in insert(.text(excerpt), label(for: excerpt, in: note)) }
                    }
                case let .writing(id):
                    NoteEditorHost(noteID: id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 560, idealHeight: 760)
        .background(Ink.paper)
        .interactiveDismissDisabled(writingID != nil)
    }

    private var writingID: UUID? {
        if case let .writing(id) = step { return id }
        return nil
    }

    private var header: some View {
        HStack(spacing: 10) {
            if step != .list, writingID == nil {
                Button {
                    step = .list
                } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zurück")
            }
            Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Spacer()
            if let hint {
                Text(hint).font(.system(size: 12)).foregroundStyle(Ink.muted).lineLimit(1)
            }
            if let id = writingID {
                Button("Verwerfen") { discard(id) }.inkButton()
                Button("Einfügen") { insertWritten(id) }.inkButton()
            } else {
                Button("Abbrechen", action: cancel).inkButton()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var title: String {
        switch step {
        case .list: "Ausschnitt einfügen"
        case let .page(id): "Bereich wählen · \(model.library.record(id)?.note.displayTitle ?? "")"
        case let .text(id): "Absätze wählen · \(model.library.record(id)?.note.displayTitle ?? "")"
        case let .writing(id): model.library.record(id)?.note.kind == .ink ? "Neue Handschrift" : "Neue Textnotiz"
        }
    }

    private var matches: [Note] {
        let all = (model.library.listing.notes(of: .ink) + model.library.listing.notes(of: .text))
            .filter { $0.id != parent.id }
            .sorted { $0.updatedAt > $1.updatedAt }
        let folded = Self.fold(query)
        guard !folded.isEmpty else { return all }
        return all.filter { Self.fold($0.displayTitle).contains(folded) || Self.fold($0.folder).contains(folded) }
    }

    private var noteList: some View {
        VStack(spacing: 10) {
            TextField("Notiz suchen", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 18)
                .padding(.top, 14)
            List {
                Section {
                    #if os(iOS)
                    newRow("Neue Handschrift", symbol: "pencil.tip.crop.circle.badge.plus", kind: .ink)
                    #endif
                    newRow("Neue Textnotiz", symbol: "doc.badge.plus", kind: .text)
                } footer: {
                    Text("Liegt dann unter \(Folders.display(childFolder)).")
                        .font(.caption)
                        .foregroundStyle(Ink.muted)
                }
                Section {
                    ForEach(matches) { note in
                        Button {
                            step = note.kind == .ink ? .page(note.id) : .text(note.id)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.displayTitle).lineLimit(1)
                                    if !note.folder.isEmpty {
                                        Text(Folders.display(note.folder)).font(.caption).foregroundStyle(Ink.muted)
                                    }
                                }
                            } icon: {
                                Image(systemName: note.kind == .ink ? "pencil.tip" : "doc.text")
                            }
                        }
                    }
                    if matches.isEmpty {
                        Text(query.isEmpty ? "Keine andere Notiz in diesem Workspace." : "Nichts passt.")
                            .foregroundStyle(Ink.muted)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .buttonStyle(.plain)
        }
    }

    private func newRow(_ title: String, symbol: String, kind: NoteKind) -> some View {
        Button {
            create(kind)
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    /// `test / doc` makes new notes in `test / doc`, next to the note `doc` in `test`.
    private var childFolder: String {
        model.library.childFolder(of: parent)
    }

    private func create(_ kind: NoteKind) {
        let fresh: Note?
        switch kind {
        case .ink: fresh = model.library.newInkNote(drawing: InkDrawing.empty())
        case .text: fresh = Note.newText()
        }
        guard let fresh else { return }
        // No title: it follows what gets written, see ADR 0019.
        let note = model.createQuietly(fresh, folder: childFolder, title: "")
        hint = nil
        step = .writing(note.id)
    }

    private func discard(_ id: UUID) {
        model.discard(id: id)
        step = .list
    }

    private func insertWritten(_ id: UUID) {
        guard let note = model.library.record(id)?.note else { return }
        switch note.kind {
        case .text:
            guard !(note.markdown ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                hint = "Noch nichts geschrieben."
                return
            }
            insert(.text(TextExcerpt(noteID: id)), note.displayTitle)
        case .ink:
            guard let page = note.pages?.first, let bounds = model.library.contentBounds(of: page) else {
                hint = "Noch nichts gezeichnet."
                return
            }
            let rect = bounds.insetBy(dx: -12, dy: -12)
            let x = max(rect.minX, 0), y = max(rect.minY, 0)
            guard let excerpt = Excerpt(
                noteID: id, pageID: page.id, x: x, y: y,
                width: min(rect.maxX, page.width) - x, height: min(rect.maxY, page.height) - y
            ) else { return }
            let label = note.displayTitle == Note.untitled ? "Handschrift" : note.displayTitle
            insert(.page(excerpt), label)
        }
    }

    private func label(for excerpt: TextExcerpt, in note: Note) -> String {
        if let section = excerpt.section, excerpt.from == nil { return "\(note.displayTitle) · \(section)" }
        return note.displayTitle
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .trimmingCharacters(in: .whitespaces)
    }
}

/// The note's own editor inside the picker, with its full tools. Follows the note as it changes.
private struct NoteEditorHost: View {
    @Environment(AppModel.self) private var model
    var noteID: UUID

    var body: some View {
        if let note = model.library.record(noteID)?.note {
            switch note.kind {
            case .ink: InkNoteView(note: note)
            case .text: TextNoteView(note: note, model: model)
            }
        }
    }
}

/// A text note shown as it reads; tapping a paragraph starts the selection, tapping another ends it.
/// A heading alone can stand for its whole section. See ADR 0037.
private struct TextRangePicker: View {
    var note: Note
    var done: (TextExcerpt) -> Void

    @State private var first: Int?
    @State private var last: Int?

    private var blocks: [Block] {
        MarkdownCodec.parse(note.markdown ?? "").filter { $0.type != .excerpt }
    }

    var body: some View {
        let blocks = blocks
        VStack(spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        TextExcerptCard.line(block, number: TextExcerptCard.number(at: index, in: blocks))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected(index) ? Ink.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture { tap(index) }
                    }
                }
                .foregroundStyle(Ink.ink)
                .padding(18)
                .frame(maxWidth: 640)
                .background(Color.white.shadow(.drop(color: .black.opacity(0.06), radius: 6, y: 2)))
                .padding(18)
            }
            footer(blocks)
        }
    }

    private func isSelected(_ index: Int) -> Bool {
        guard let first else { return false }
        let end = last ?? first
        return (min(first, end)...max(first, end)).contains(index)
    }

    private func tap(_ index: Int) {
        if first == nil || last != nil {
            first = index
            last = nil
        } else {
            last = index
        }
    }

    private var range: ClosedRange<Int>? {
        guard let first else { return nil }
        let end = last ?? first
        return min(first, end)...max(first, end)
    }

    /// The selection as an excerpt, if it finds exactly these paragraphs again.
    private func excerpt(_ blocks: [Block]) -> TextExcerpt? {
        guard let range else { return nil }
        let start = blocks[range.lowerBound], end = blocks[range.upperBound]
        let heading = blocks[...range.lowerBound].last { [.heading1, .heading2, .heading3].contains($0.type) }?.plain
        let markdown = note.markdown ?? ""
        let wanted = blocks[range].map(\.plain)
        for section in [heading, nil] {
            let candidate = TextExcerpt(noteID: note.id, section: section, from: start.plain, to: end.plain)
            if MarkdownCodec.blocks(for: candidate, in: markdown)?.map(\.plain) == wanted { return candidate }
        }
        return nil
    }

    private func footer(_ blocks: [Block]) -> some View {
        let picked = excerpt(blocks)
        let heading = range.flatMap { range -> String? in
            guard range.count == 1, [.heading1, .heading2, .heading3].contains(blocks[range.lowerBound].type) else { return nil }
            return blocks[range.lowerBound].plain
        }
        return HStack(spacing: 12) {
            Text(range == nil ? "Absatz antippen, dann den letzten" : (picked == nil ? "Diese Auswahl lässt sich nicht eindeutig merken" : ""))
                .font(.system(size: 13))
                .foregroundStyle(Ink.muted)
            Spacer()
            Button("Ganze Notiz") { done(TextExcerpt(noteID: note.id)) }
                .inkButton()
            if let heading {
                Button("Ganzer Abschnitt") { done(TextExcerpt(noteID: note.id, section: heading)) }
                    .inkButton()
            }
            Button("Einfügen") { if let picked { done(picked) } }
                .inkButton()
                .disabled(picked == nil)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }
}

/// One page of a note, shown whole; a drag draws the rectangle. Several pages switch with arrows.
private struct PageAreaPicker: View {
    @Environment(AppModel.self) private var model
    var note: Note
    var done: (Excerpt) -> Void

    @State private var pageIndex = 0
    @State private var start: CGPoint?
    @State private var area: CGRect?

    var body: some View {
        let pages = note.pages ?? []
        VStack(spacing: 10) {
            if pages.indices.contains(pageIndex) {
                let page = pages[pageIndex]
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / page.width, 1.4)
                    ScrollView(.vertical) {
                        pageView(page, scale: scale)
                            .frame(width: page.width * scale, height: page.height * scale)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Text("Diese Notiz hat keine Seite.")
                    .foregroundStyle(Ink.muted)
                    .frame(maxHeight: .infinity)
            }
            footer(pages)
        }
        .padding(.top, 10)
        .onChange(of: pageIndex) { _, _ in area = nil }
    }

    private func pageView(_ page: InkPage, scale: CGFloat) -> some View {
        let whole = Excerpt(noteID: note.id, pageID: page.id, x: 0, y: 0, width: page.width, height: page.height)
        let rendered: CGImage? = whole.flatMap { excerpt in
            if case let .image(image, _) = ExcerptRenderer.render(excerpt, source: source) { return image }
            return nil
        }
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            if let rendered {
                Image(decorative: rendered, scale: CGFloat(rendered.width) / page.width / scale)
                    .resizable()
            }
            if let area {
                let shown = CGRect(x: area.minX * scale, y: area.minY * scale, width: area.width * scale, height: area.height * scale)
                Path { path in
                    path.addRect(CGRect(x: 0, y: 0, width: page.width * scale, height: page.height * scale))
                    path.addRect(shown)
                }
                .fill(Color.black.opacity(0.12), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Ink.accent, lineWidth: 2)
                    .frame(width: shown.width, height: shown.height)
                    .offset(x: shown.minX, y: shown.minY)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let origin = start ?? value.startLocation
                    start = origin
                    let a = CGPoint(x: origin.x / scale, y: origin.y / scale)
                    let b = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                    let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                    area = rect.intersection(CGRect(x: 0, y: 0, width: page.width, height: page.height))
                }
                .onEnded { _ in start = nil }
        )
    }

    private func footer(_ pages: [InkPage]) -> some View {
        HStack(spacing: 12) {
            if pages.count > 1 {
                Button {
                    pageIndex = max(pageIndex - 1, 0)
                } label: { Image(systemName: "chevron.up") }
                    .disabled(pageIndex == 0)
                Text("Seite \(pageIndex + 1) von \(pages.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                Button {
                    pageIndex = min(pageIndex + 1, pages.count - 1)
                } label: { Image(systemName: "chevron.down") }
                    .disabled(pageIndex >= pages.count - 1)
            }
            Spacer()
            Text(area == nil ? "Rechteck über den Bereich ziehen" : "")
                .font(.system(size: 13))
                .foregroundStyle(Ink.muted)
            Button("Ganze Seite") { insert(pages, whole: true) }
                .inkButton()
                .disabled(!pages.indices.contains(pageIndex))
            Button("Einfügen") { insert(pages, whole: false) }
                .inkButton()
                .disabled(area == nil || (area?.width ?? 0) < 8 || (area?.height ?? 0) < 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private func insert(_ pages: [InkPage], whole: Bool) {
        guard pages.indices.contains(pageIndex) else { return }
        let page = pages[pageIndex]
        let rect = whole ? CGRect(x: 0, y: 0, width: page.width, height: page.height) : (area ?? .zero)
        guard let excerpt = Excerpt(
            noteID: note.id, pageID: page.id, x: rect.minX, y: rect.minY, width: rect.width, height: rect.height
        ) else { return }
        done(excerpt)
    }

    private var source: ExcerptSource { .current }
}

