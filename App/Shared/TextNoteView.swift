import InkhashCore
import SwiftUI

struct TextNoteView: View {
    @State private var session: TextSession
    @Environment(AppModel.self) private var model
    @State private var compact = false
    @State private var showsPaper = false

    /// Title and path start where the text starts, right of the marker column.
    static var gutter: CGFloat { NoteDocument.gutter }

    init(note: Note, model: AppModel) {
        _session = State(initialValue: TextSession(note: note, model: model))
    }

    var body: some View {
        let record = model.record(session.noteID)
        let state = session.state
        ScrollViewReader { proxy in
            ScrollView {
                // The sheet is the whole surface, see ADR 0018. The column keeps lines readable.
                VStack(alignment: .leading, spacing: 0) {
                    NoteHeader(noteID: session.noteID)
                        .padding(.leading, Self.gutter)
                        .padding(.bottom, 12)
                        // Path proposals hang over the text below.
                        .zIndex(2)
                    if record?.conflict == true {
                        ConflictBanner(noteID: session.noteID)
                            .padding(.leading, Self.gutter)
                    }
                    NoteTextView(session: session, version: session.version)
                        .overlay(alignment: .topLeading) { overlays(state) }
                        // Menus hang below the text; they must stay above the empty area after it.
                        .zIndex(1)
                    Color.clear
                        .frame(height: 240)
                        .contentShape(Rectangle())
                        .onTapGesture { session.focusEnd() }
                }
                // A narrow screen keeps its width for the text, see ADR 0026.
                .padding(.horizontal, compact ? 16 : 36)
                .padding(.top, compact ? 12 : 22)
                .frame(maxWidth: 760, alignment: .top)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: state.caret) { _, _ in
                // Without an anchor the scroll view moves only as far as needed.
                proxy.scrollTo(Self.caretID)
            }
        }
        // A text note has a colour only, no pattern. See ADR 0042.
        .background((record?.note.shownPaper ?? .standard).fill.ignoresSafeArea())
        .compactWidth($compact)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsPaper = true } label: { Image(systemName: "paintpalette") }
                    .accessibilityLabel("Papierfarbe")
                    .popover(isPresented: $showsPaper) {
                        PaperPicker(paper: record?.note.shownPaper ?? .standard, patterns: false) {
                            model.setPaper(noteID: session.noteID, paper: $0)
                        }
                    }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: Binding(get: { session.excerptInsert }, set: { if !$0 { session.cancelExcerptInsert() } })) {
            ExcerptPicker(parent: record?.note ?? Note.newText()) { excerpt, label in
                session.insertExcerpt(excerpt, label: label)
            } cancel: {
                session.cancelExcerptInsert()
            }
            .environment(model)
        }
        .onChange(of: model.inlineImpulse) { _, impulse in
            if let impulse { session.toggleInline(impulse.action) }
        }
        .onChange(of: model.linkPromptToken) { _, _ in
            if session.state.selection.length > 0 { session.linkPrompt = true }
        }
    }

    private static let caretID = "caret"

    @ViewBuilder
    private func overlays(_ state: EditorState) -> some View {
        Color.clear
            .frame(width: 1, height: max(state.caret.height, 1))
            .offset(x: state.caret.minX, y: state.caret.minY)
            .id(Self.caretID)
            .allowsHitTesting(false)
        // `/Link` asks for target and label at the cursor. See ADR 0031.
        Color.clear
            .allowsHitTesting(false)
            .popover(
                isPresented: Binding(get: { session.linkInsert }, set: { if !$0 { session.cancelLinkInsert() } }),
                attachmentAnchor: .rect(.rect(CGRect(x: state.caret.minX, y: state.caret.minY, width: 1, height: max(state.caret.height, 1)))),
                arrowEdge: .bottom
            ) {
                LinkInsertEditor(excluding: session.noteID) { label, target in
                    session.insertLink(label: label, target: target)
                } cancel: {
                    session.cancelLinkInsert()
                }
            }
        if let rect = state.selectionRect, state.selection.length > 0, state.blockType != .code {
            FormatBar(
                type: state.blockType,
                selection: state.selection,
                linkPrompt: Binding(get: { session.linkPrompt }, set: { session.linkPrompt = $0 }),
                setType: { session.setType($0) },
                toggle: { session.toggleInline($0) },
                setLink: { session.setLink($0) },
                noteID: session.noteID
            )
            .offset(x: max(0, rect.minX - 8), y: max(-40, rect.minY - 44))
        } else if let target = state.caretLink, state.slashQuery == nil, state.noteQuery == nil {
            OpenLinkChip(target: target)
                .offset(x: max(0, state.caret.minX - 8), y: max(-34, state.caret.minY - 32))
        }
        if let table = state.table {
            TableMenu(format: table, column: state.tableColumn, columns: state.tableColumns) { change in
                session.changeTable(change)
            }
            .offset(x: 2, y: state.caret.minY + (state.caret.height - 26) / 2)
        }
        if state.noteQuery != nil {
            NoteLinkMenu(notes: session.noteSuggestions, index: session.noteIndex) {
                session.applyNoteLink($0)
            }
            .offset(x: Self.gutter, y: state.caret.maxY)
        }
        if state.slashQuery != nil {
            SlashMenu(commands: session.commands, index: session.slashIndex) {
                session.slashIndex = $0
                session.applySlash()
            }
            .offset(x: Self.gutter, y: state.caret.maxY)
        }
    }
}

/// Floats above the focused block while text is marked: block type on the left, inline styles on the right.
/// It exists only with a selection; without one the sheet stays bare. See ADR 0023.
struct FormatBar: View {
    var type: BlockType
    var selection: InlineSelection
    @Binding var linkPrompt: Bool
    var setType: (BlockType) -> Void
    var toggle: (EditorAction) -> Void
    var setLink: (String?) -> Void
    var noteID: UUID?

    private static let types: [SlashCommand] = [.paragraph, .heading1, .heading2, .heading3, .bullet, .numbered, .checkbox, .code, .table]

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(Self.types) { command in
                    Button {
                        if let next = command.blockType { setType(next) }
                    } label: {
                        if command.blockType == type {
                            Label(command.title, systemImage: "checkmark")
                        } else {
                            Text(command.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(Self.types.first { $0.blockType == type }?.title ?? "Text")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.ink)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            styleButton("bold", on: selection.bold, help: "Fett") { toggle(.toggleBold) }
            styleButton("italic", on: selection.italic, help: "Kursiv") { toggle(.toggleItalic) }
            styleButton("chevron.left.forwardslash.chevron.right", on: selection.code, help: "Code im Text") { toggle(.toggleCode) }
            styleButton("link", on: selection.link != nil, help: "Link") {
                linkPrompt = true
            }
            .popover(isPresented: $linkPrompt, arrowEdge: .top) {
                linkEditor
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .inkPanel(radius: 12)
    }

    private var linkEditor: some View {
        LinkEditor(current: selection.link, excluding: noteID, set: setLink)
    }

    private func styleButton(_ symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Ink.accent : Ink.ink)
                .frame(width: 30, height: 28)
                .background(on ? Ink.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Settings of the table the cursor is in, from a small button in the margin. See ADR 0036.
struct TableMenu: View {
    var format: TableFormat
    var column: Int
    var columns: Int
    var change: ((inout TableFormat, Int, Int) -> Void) -> Void

    var body: some View {
        Menu {
            if column > 0 {
                Picker("Spalte \(column + 1) ausrichten", selection: Binding(
                    get: { format.alignment(of: column) },
                    set: { next in change { format, column, columns in format.setAlignment(next, of: column, columns: columns) } }
                )) {
                    Label("Links", systemImage: "text.alignleft").tag(TableFormat.Alignment.left)
                    Label("Mitte", systemImage: "text.aligncenter").tag(TableFormat.Alignment.center)
                    Label("Rechts", systemImage: "text.alignright").tag(TableFormat.Alignment.right)
                }
                .pickerStyle(.inline)
            }
            if columns > 1 {
                Section("Spalte \(column + 1)") {
                    Button("Breiter", systemImage: "arrow.left.and.right") {
                        change { format, column, columns in format = format.resizing(column: column, by: 0.08, columns: columns) }
                    }
                    Button("Schmaler", systemImage: "arrow.right.and.line.vertical.and.arrow.left") {
                        change { format, column, columns in format = format.resizing(column: column, by: -0.08, columns: columns) }
                    }
                    if !format.widths.isEmpty {
                        Button("Gleich breit", systemImage: "equal") { change { format, _, _ in format.widths = [] } }
                    }
                }
            }
            Section("Tabelle") {
                Toggle("Kopfzeile", isOn: Binding(get: { format.header }, set: { on in change { format, _, _ in format.header = on } }))
                Toggle("Zebrastreifen", isOn: Binding(get: { format.zebra }, set: { on in change { format, _, _ in format.zebra = on } }))
            }
        } label: {
            Image(systemName: "tablecells")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Ink.muted)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tabelle")
        .accessibilityLabel("Tabelle einstellen")
    }
}

struct SlashMenu: View {
    var commands: [SlashCommand]
    var index: Int
    var select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if commands.isEmpty {
                Text("Nichts passt")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                    .padding(10)
            }
            ForEach(Array(commands.enumerated()), id: \.element.id) { offset, command in
                HStack {
                    Text(command.title)
                    Spacer()
                    Text(command.hint)
                        .foregroundStyle(Ink.muted)
                }
                .font(.system(size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(offset == index ? Ink.accent.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { select(offset) }
            }
        }
        .frame(width: 280)
        .padding(.vertical, 4)
        .inkSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 6)
    }
}

struct ConflictBanner: View {
    @Environment(AppModel.self) private var model
    var noteID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Auf dem Server liegt eine andere Fassung.")
                .font(.system(size: 14, design: .serif))
            HStack {
                Button("Meine behalten") { model.keepMine(id: noteID) }
                    .inkButton()
                Button("Server nehmen") { model.takeServer(id: noteID) }
                    .inkButton()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 16)
    }
}

/// Title and path, top left on the sheet, each a plain line that turns into a field on click.
/// An empty title hands the title back to the content (ADR 0019); an empty path puts the note
/// at the root of the workspace. See ADR 0022.
struct NoteHeader: View {
    @Environment(AppModel.self) private var model
    var noteID: UUID

    var body: some View {
        let note = model.record(noteID)?.note
        VStack(alignment: .leading, spacing: 3) {
            InlineField(
                value: note.map { $0.hasAutomaticTitle ? "" : $0.title } ?? "",
                shown: note?.displayTitle ?? Note.untitled,
                placeholder: note?.automaticTitle ?? Note.untitled,
                help: "Titel ändern",
                font: .system(size: 13, weight: .medium),
                color: Ink.ink
            ) { model.rename(id: noteID, title: $0) }
            InlineField(
                value: note.map { Folders.display($0.folder) } ?? "",
                shown: note.map { $0.folder.isEmpty ? "" : Folders.display($0.folder) } ?? "",
                placeholder: "Pfad, z. B. Projekt / Treffen",
                help: "Pfad ändern",
                font: .system(size: 12),
                color: Ink.muted,
                literal: true,
                suggestions: { PathSuggestions.for($0, folders: model.folders) }
            ) { model.setFolder(id: noteID, typed: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A line of text that becomes a field on click and hands its text back when done.
struct InlineField: View {
    /// What the field starts with when editing.
    var value: String
    /// What stands there while not editing. Empty shows the placeholder, muted.
    var shown: String
    var placeholder: String
    var help: String
    var font: Font
    var color: Color
    /// Typed as is: no automatic capitals or corrections. Capitals only when typed by hand.
    var literal = false
    /// Proposals for what is typed so far; picking one replaces the draft. Nil shows none.
    var suggestions: ((String) -> [String])? = nil
    var commit: (String) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(finish)
                    #if os(iOS)
                    .textInputAutocapitalization(literal ? .never : .sentences)
                    .autocorrectionDisabled(literal)
                    #endif
                    .onChange(of: focused) { _, isFocused in
                        // A tap on a proposal takes the focus for a moment; finish only if it stays away.
                        guard !isFocused else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if !focused { finish() }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let suggestions, focused {
                            let proposals = suggestions(draft)
                            if !proposals.isEmpty {
                                proposalList(proposals)
                                    .offset(y: 22)
                            }
                        }
                    }
                    #if os(macOS)
                    .onExitCommand(perform: { editing = false })
                    #endif
            } else {
                Button {
                    draft = value
                    editing = true
                    focused = true
                } label: {
                    Text(shown.isEmpty ? placeholder : shown)
                        .foregroundStyle(shown.isEmpty ? Ink.muted.opacity(0.6) : color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help)
                .accessibilityHint(help)
            }
        }
        .font(font)
        .foregroundStyle(color)
    }

    private func proposalList(_ proposals: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(proposals, id: \.self) { proposal in
                Button {
                    draft = proposal
                    focused = true
                } label: {
                    Text(proposal)
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 280)
        .padding(4)
        .inkPanel(radius: 12)
    }

    private func finish() {
        guard editing else { return }
        commit(draft)
        editing = false
    }
}

/// Proposals for the path field. Empty: the existing paths. After a `/`: the folders one level below
/// what is typed, matching the part after the slash. Otherwise: paths containing the text. See ADR 0027.
enum PathSuggestions {
    static func `for`(_ typed: String, folders: [String], limit: Int = 8) -> [String] {
        let parts = typed.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE")) }
        if parts.count > 1 {
            let parent = parts.dropLast().filter { !$0.isEmpty }.joined(separator: "/")
            let partial = fold(parts.last ?? "")
            return folders
                .filter { Folders.parent(of: $0) == parent }
                .filter { partial.isEmpty || fold(Folders.name(of: $0)).hasPrefix(partial) }
                .sorted()
                .prefix(limit)
                .map(Folders.display)
        }
        let needle = fold(typed.trimmingCharacters(in: .whitespaces))
        let current = typed.trimmingCharacters(in: .whitespaces)
        return folders
            .filter { needle.isEmpty || fold($0).contains(needle) }
            .sorted { Folders.depth(of: $0) == Folders.depth(of: $1) ? $0 < $1 : Folders.depth(of: $0) < Folders.depth(of: $1) }
            .map(Folders.display)
            .filter { $0 != current }
            .prefix(limit)
            .map { $0 }
    }
}
