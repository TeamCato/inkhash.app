import InkhashCore
import SwiftUI

/// Where a link goes: a web or mail address, or a note found by typing part of its title. Used for
/// text and for areas on a page. An empty field removes the link. See ADR 0027, 0028 and 0031.
struct LinkEditor: View {
    @Environment(AppModel.self) private var model
    var current: String?
    var excluding: UUID?
    var set: (String?) -> Void

    @State private var draft = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LinkTargetField(draft: $draft, invalid: $invalid, current: current, excluding: excluding) { record in
                set(NoteLink.target(for: record.id))
            } submit: {
                commit()
            }
            HStack(spacing: 8) {
                if let current {
                    Button("Öffnen") { model.openLink(current) }
                        .font(.system(size: 13))
                    Spacer()
                    Button("Entfernen") { set(nil) }
                        .font(.system(size: 13))
                } else {
                    Spacer()
                }
                Button("Setzen") { commit() }
                    .font(.system(size: 13, weight: .semibold))
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { draft = current.flatMap { NoteLink.noteID(in: $0) == nil ? $0 : nil } ?? "" }
        #if os(iOS)
        .presentationCompactAdaptation(.popover)
        #endif
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { set(nil); return }
        switch LinkTargetField.resolve(trimmed, model: model, excluding: excluding) {
        case .note(let record): set(NoteLink.target(for: record.id))
        case .address(let target): set(target)
        case .invalid: invalid = true
        }
    }
}

/// Asked by `/Link` in a text note: first where the link goes, then what it says. An empty label
/// takes the note title or the host of the address. See ADR 0031.
struct LinkInsertEditor: View {
    @Environment(AppModel.self) private var model
    var excluding: UUID?
    var insert: (_ label: String, _ target: String) -> Void
    var cancel: () -> Void

    @State private var draft = ""
    @State private var label = ""
    @State private var invalid = false
    @State private var picked: NoteRecord?
    @FocusState private var focus: Field?

    private enum Field { case target, label }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link einfügen")
                .font(.system(size: 13, weight: .semibold))
            if let picked {
                HStack(spacing: 8) {
                    Image(systemName: picked.note.kind == .ink ? "pencil.tip" : "doc.text")
                        .foregroundStyle(Ink.muted)
                        .frame(width: 16)
                    Text(picked.note.displayTitle).lineLimit(1)
                    Spacer()
                    Button {
                        self.picked = nil
                        focus = .target
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Andere Notiz wählen")
                }
                .font(.system(size: 13))
                .padding(.vertical, 4)
            } else {
                LinkTargetField(draft: $draft, invalid: $invalid, current: nil, excluding: excluding) { record in
                    picked = record
                    focus = .label
                } submit: {
                    focus = .label
                }
                .focused($focus, equals: .target)
            }
            TextField(labelPlaceholder, text: $label)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($focus, equals: .label)
                .onSubmit { commit() }
            HStack(spacing: 8) {
                Button("Abbrechen", role: .cancel) { cancel() }
                    .font(.system(size: 13))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Einfügen") { commit() }
                    .font(.system(size: 13, weight: .semibold))
                    .keyboardShortcut(.defaultAction)
                    .disabled(picked == nil && draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { focus = .target }
        #if os(iOS)
        .presentationCompactAdaptation(.popover)
        #endif
    }

    private var labelPlaceholder: String {
        if let picked { return picked.note.displayTitle }
        if let target = LinkTarget.normalize(draft) { return LinkTarget.defaultLabel(for: target) }
        return "Text des Links"
    }

    private func commit() {
        let target: String
        let fallback: String
        if let picked {
            target = NoteLink.target(for: picked.id)
            fallback = picked.note.displayTitle
        } else {
            switch LinkTargetField.resolve(draft, model: model, excluding: excluding) {
            case .note(let record):
                target = NoteLink.target(for: record.id)
                fallback = record.note.displayTitle
            case .address(let address):
                target = address
                fallback = LinkTarget.defaultLabel(for: address)
            case .invalid:
                invalid = true
                focus = .target
                return
            }
        }
        let typed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        insert(typed.isEmpty ? fallback : typed, target)
    }
}

/// The target field both editors share: typing a title proposes notes, anything else is an address.
struct LinkTargetField: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: String
    @Binding var invalid: Bool
    var current: String?
    var excluding: UUID?
    var pick: (NoteRecord) -> Void
    var submit: () -> Void

    enum Resolution {
        case note(NoteRecord)
        case address(String)
        case invalid
    }

    /// A typed title that matches exactly one note links to it; an address is normalized; the rest is no link.
    static func resolve(_ input: String, model: AppModel, excluding: UUID?) -> Resolution {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !LinkTarget.looksLikeAddress(trimmed) {
            let matches = model.linkableNotes(matching: trimmed, excluding: excluding, limit: 2)
            if matches.count == 1, let only = matches.first { return .note(only) }
        }
        if let target = LinkTarget.normalize(trimmed) { return .address(target) }
        return .invalid
    }

    var body: some View {
        let suggestions = LinkTarget.looksLikeAddress(draft) ? [] : model.linkableNotes(matching: draft, excluding: excluding, limit: 6)
        VStack(alignment: .leading, spacing: 6) {
            TextField("Notiz suchen oder Adresse", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit { submit() }
                .onChange(of: draft) { _, _ in invalid = false }
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
            if invalid {
                Text("Keine Notiz und keine gültige Adresse. Erlaubt sind Webadressen und E-Mail.")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions) { record in
                        Button {
                            pick(record)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: record.note.kind == .ink ? "pencil.tip" : "doc.text")
                                    .foregroundStyle(Ink.muted)
                                    .frame(width: 16)
                                Text(record.note.displayTitle)
                                    .lineLimit(1)
                                Spacer()
                                if current == NoteLink.target(for: record.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Ink.accent)
                                }
                            }
                            .font(.system(size: 13))
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// The `[[` menu under the cursor: notes whose title matches what follows the brackets.
struct NoteLinkMenu: View {
    var notes: [NoteRecord]
    var index: Int
    var select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if notes.isEmpty {
                Text("Keine passende Notiz")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.muted)
                    .padding(10)
            }
            ForEach(Array(notes.enumerated()), id: \.element.id) { offset, record in
                HStack(spacing: 8) {
                    Image(systemName: record.note.kind == .ink ? "pencil.tip" : "doc.text")
                        .foregroundStyle(Ink.muted)
                        .frame(width: 16)
                    Text(record.note.displayTitle).lineLimit(1)
                    Spacer()
                    if !record.note.folder.isEmpty {
                        Text(Folders.display(record.note.folder))
                            .foregroundStyle(Ink.muted)
                            .lineLimit(1)
                    }
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
        .frame(width: 320)
        .padding(4)
        .inkPanel(radius: 14)
        .padding(.top, 6)
    }
}

/// Shown at the cursor while it stands in a link: one tap follows it.
struct OpenLinkChip: View {
    @Environment(AppModel.self) private var model
    var target: String

    var body: some View {
        Button {
            model.openLink(target)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: NoteLink.noteID(in: target) == nil ? "arrow.up.right" : "doc.text")
                Text(label).lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Ink.accent)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .inkPanel(radius: 13)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Link öffnen")
    }

    private var label: String {
        if let id = NoteLink.noteID(in: target) {
            return model.record(id)?.note.displayTitle ?? "Notiz fehlt"
        }
        return Links.url(target)?.host() ?? target
    }
}
