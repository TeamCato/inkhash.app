import Foundation
import InkhashCore
import Observation

/// State of one open text note between the sheet and its editor. The text itself lives in the editor. See ADR 0025.
@MainActor
@Observable
final class TextSession {
    let noteID: UUID
    private let model: AppModel
    /// What the editor starts with. Not kept in sync; the editor owns the text after that.
    let initialBlocks: [Block]
    @ObservationIgnored weak var engine: EditorEngine?
    var state = EditorState()
    var version = 0
    var slashIndex = 0
    var noteIndex = 0
    /// True while the link field of the format bar is open, also after Cmd+K.
    var linkPrompt = false
    /// True while `/Link` asks for target and label. See ADR 0031.
    var linkInsert = false
    /// True while `/Ausschnitt` shows the picker. See ADR 0035.
    var excerptInsert = false

    init(note: Note, model: AppModel) {
        noteID = note.id
        self.model = model
        initialBlocks = MarkdownCodec.parse(note.markdown ?? "")
    }

    /// Excerpts draw pages of the current workspace only. See ADR 0032.
    var excerptSource: ExcerptSource {
        ExcerptSource(
            note: { [model] id in model.library.record(id)?.note },
            loadBlob: { [model] blob in model.library.drawingData(for: blob) }
        )
    }

    var commands: [SlashCommand] {
        let query = (state.slashQuery ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        let offered = SlashCommand.allCases.filter { command in
            if state.slashInline, !command.fitsInline { return false }
            // A table or code block takes an empty line; it would swallow the text after the cursor.
            if command == .table || command == .code { return state.slashLineEmpty }
            return true
        }
        guard !query.isEmpty else { return offered }
        return offered.filter {
            $0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE")).contains(query)
                || $0.hint.contains(query)
        }
    }

    func commit(_ blocks: [Block]) {
        model.library.updateMarkdown(id: noteID, markdown: MarkdownCodec.serialize(blocks))
        version += 1
    }

    func update(_ next: EditorState) {
        if state != next { state = next }
        if next.noteQuery == nil { noteIndex = 0 }
        if next.slashQuery == nil {
            slashIndex = 0
        } else {
            let count = commands.count
            if slashIndex >= count { slashIndex = max(0, count - 1) }
        }
    }

    /// Notes for the `[[` menu: titles that contain the query, the current note left out. See ADR 0027.
    var noteSuggestions: [NoteRecord] {
        guard let query = state.noteQuery else { return [] }
        return model.library.listing.linkable(matching: query, excluding: noteID)
    }

    func moveNoteLink(_ delta: Int) {
        let count = max(noteSuggestions.count, 1)
        noteIndex = (noteIndex + delta + count) % count
    }

    func applyNoteLink(_ index: Int? = nil) {
        let choices = noteSuggestions
        guard !choices.isEmpty else { return }
        let record = choices[min(index ?? noteIndex, choices.count - 1)]
        noteIndex = 0
        engine?.insertNoteLink(title: record.note.displayTitle, target: NoteLink.target(for: record.id))
    }

    func escapeNoteLink() {
        engine?.escapeNoteLink()
    }

    func openLink(_ target: String) {
        model.openLink(target)
    }

    func moveSlash(_ delta: Int) {
        let count = max(commands.count, 1)
        slashIndex = (slashIndex + delta + count) % count
    }

    func applySlash() {
        let choices = commands
        guard !choices.isEmpty else { return }
        let command = choices[min(slashIndex, choices.count - 1)]
        slashIndex = 0
        engine?.applySlash(command)
        if command == .link { linkInsert = true }
        if command == .excerpt { excerptInsert = true }
    }

    func insertLink(label: String, target: String) {
        linkInsert = false
        engine?.insertLink(label: label, target: target)
    }

    func changeTable(_ change: (inout TableFormat, _ column: Int, _ columns: Int) -> Void) {
        engine?.changeTable(change)
    }

    func insertExcerpt(_ excerpt: ExcerptTarget, label: String) {
        excerptInsert = false
        engine?.insertExcerpt(excerpt, label: label)
    }

    func cancelExcerptInsert() {
        excerptInsert = false
        engine?.focus()
    }

    func cancelLinkInsert() {
        linkInsert = false
        engine?.focus()
    }

    func setType(_ type: BlockType) {
        engine?.setType(type)
    }

    func toggleInline(_ action: EditorAction) {
        engine?.toggle(action)
    }

    /// The editors hand over normalized targets; anything else removes the link. See ADR 0031.
    func setLink(_ target: String?) {
        linkPrompt = false
        engine?.setLink(target.flatMap { LinkTarget.normalize($0) })
    }

    func focusEnd() {
        engine?.focusEnd()
    }
}

enum SlashCommand: String, CaseIterable, Identifiable {
    case paragraph
    case heading1
    case heading2
    case heading3
    case bullet
    case numbered
    case checkbox
    case code
    case table
    case link
    case excerpt
    case bold
    case italic
    case inlineCode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paragraph: return "Text"
        case .heading1: return "Überschrift 1"
        case .heading2: return "Überschrift 2"
        case .heading3: return "Überschrift 3"
        case .bullet: return "Liste"
        case .numbered: return "Nummerierte Liste"
        case .checkbox: return "Aufgabe"
        case .code: return "Code"
        case .table: return "Tabelle"
        case .link: return "Link"
        case .excerpt: return "Ausschnitt"
        case .bold: return "Fett"
        case .italic: return "Kursiv"
        case .inlineCode: return "Code im Text"
        }
    }

    var hint: String {
        switch self {
        case .paragraph: return ""
        case .heading1: return "#"
        case .heading2: return "##"
        case .heading3: return "###"
        case .bullet: return "-"
        case .numbered: return "1."
        case .checkbox: return "[ ]"
        case .code: return "```"
        case .table: return "|"
        case .link: return "[]()"
        case .excerpt: return "✎"
        case .bold: return "**"
        case .italic: return "*"
        case .inlineCode: return "`"
        }
    }

    var blockType: BlockType? {
        switch self {
        case .paragraph: return .paragraph
        case .heading1: return .heading1
        case .heading2: return .heading2
        case .heading3: return .heading3
        case .bullet: return .bullet
        case .numbered: return .numbered
        case .checkbox: return .checkbox
        case .code: return .code
        case .table: return .tableRow
        case .link, .excerpt, .bold, .italic, .inlineCode: return nil
        }
    }

    /// Offered after text in a paragraph. Headings, code blocks and tables only start a line. See ADR 0033.
    var fitsInline: Bool {
        switch self {
        case .heading1, .heading2, .heading3, .code, .table: return false
        default: return true
        }
    }

    var inlineAction: EditorAction? {
        switch self {
        case .bold: return .toggleBold
        case .italic: return .toggleItalic
        case .inlineCode: return .toggleCode
        default: return nil
        }
    }
}
