import InkhashCore
import SwiftUI
import UniformTypeIdentifiers

/// Workspace, search, then the tree of that workspace: folders with their notes as leaves. "#tag" in
/// the search field thins the tree to that tag. Favorites and trash are flat lists behind the footer.
/// See ADR 0022.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var showSettings: Bool
    @FocusState private var searchFocused: Bool
    @State private var folderPrompt: FolderPrompt?
    @State private var folderName = ""
    @State private var pendingRemoval: String?
    @State private var pendingDelete: UUID?
    @State private var confirmEmptyTrash = false
    @State private var newWorkspace = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            InkhashLogo(markSide: 22, wordSize: 17)
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            WorkspaceSwitcher(newWorkspace: $newWorkspace, showSettings: $showSettings)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            HStack(spacing: 0) {
                searchField
                newMenu
            }
            if model.tagFilter != nil {
                tagSuggestions
            }
            if let server = model.expiredNotice {
                ExpiredSessionBanner(server: server, showSettings: $showSettings)
            }
            if isSearching {
                flatList(title: nil)
            } else if model.section == .notes {
                tree
            } else {
                flatList(title: model.section.title)
            }
            footer
        }
        .onChange(of: model.searchFocusToken) { _, _ in
            searchFocused = true
        }
        .alert(folderPrompt?.title ?? "", isPresented: Binding(get: { folderPrompt != nil }, set: { if !$0 { folderPrompt = nil } })) {
            TextField("Name", text: $folderName)
            Button("Abbrechen", role: .cancel) { folderPrompt = nil }
            Button(folderPrompt?.action ?? "OK") { commitFolder() }
        }
        .confirmationDialog(
            "Ordner entfernen?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ordner entfernen", role: .destructive) {
                if let pendingRemoval { model.library.removeFolder(pendingRemoval) }
                pendingRemoval = nil
            }
            Button("Abbrechen", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Die Notizen darin bleiben erhalten und rücken eine Ebene nach oben.")
        }
        .confirmationDialog(
            "Diese Notiz in den Papierkorb legen?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("In den Papierkorb", role: .destructive) {
                if let pendingDelete { model.delete(id: pendingDelete) }
                pendingDelete = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDelete = nil }
        }
        .confirmationDialog("Papierkorb leeren?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) { model.emptyTrash() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Notizen, deren Löschung noch nicht abgeglichen ist, bleiben bis nach dem Abgleich liegen.")
        }
        .sheet(isPresented: $newWorkspace) {
            NavigationStack {
                WorkspaceEditor(workspace: nil)
            }
            .macSheetSize(minWidth: 440, minHeight: 420)
        }
    }

    /// Text searches show a flat list; a "#tag" filter keeps the tree.
    private var isSearching: Bool {
        !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.tagFilter == nil
    }

    // MARK: Search

    private var searchField: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Ink.muted)
            TextField(searchPrompt, text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Ink.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche leeren")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .inkSurface(in: Capsule())
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.bottom, 8)
    }

    private var searchPrompt: String {
        switch model.section {
        case .notes: "Suchen oder #schlagwort"
        default: "In \(model.section.title) suchen"
        }
    }

    /// The tags that match what stands after the "#". A tap completes the filter.
    private var tagSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if model.suggestedTags.isEmpty {
                    Text(model.library.listing.tagCounts.isEmpty ? "Noch keine Schlagwörter." : "Kein Schlagwort beginnt so.")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.muted)
                        .padding(.vertical, 5)
                }
                ForEach(model.suggestedTags) { item in
                    let chosen = model.tagFilter == item.tag
                    Button {
                        model.query = "#\(item.tag)"
                    } label: {
                        HStack(spacing: 4) {
                            Text("#\(item.tag)")
                                .font(.system(size: 12, weight: .medium))
                            Text("\(item.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(Ink.muted)
                                .monospacedDigit()
                        }
                        .foregroundStyle(chosen ? Ink.paper : Ink.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if chosen {
                                Capsule().fill(Ink.accent)
                            }
                        }
                        .inkSurface(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schlagwort \(item.tag), \(item.count) Notizen")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 8)
    }

    private var newMenu: some View {
        @Bindable var model = model
        return Menu {
            Button("Textnotiz", systemImage: "doc.text") { model.createText() }
            Button("Stiftnotiz", systemImage: "pencil.tip") { model.createInk(data: InkDrawing.empty()) }
            Divider()
            Button("Ordner", systemImage: "folder.badge.plus") { ask(.create(parent: "")) }
            Divider()
            Button("PDF oder GoodNotes importieren…", systemImage: "square.and.arrow.down") { model.importRequested = true }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Ink.paper)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Ink.accent))
                .shadow(color: Ink.accent.opacity(0.35), radius: 4, y: 2)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Neu")
        .padding(.trailing, 6)
        .padding(.bottom, 8)
        .fileImporter(isPresented: $model.importRequested, allowedContentTypes: [.pdf, .goodnotes]) { result in
            if case .success(let url) = result { model.importFile(at: url) }
        }
    }

    // MARK: Tree

    private var tree: some View {
        List(selection: Bindable(model).selectedID) {
            let root = model.folderTree
            if root.isEmpty {
                hint(model.tagFilter == nil ? "Noch keine Notizen." : "Keine Notiz mit diesem Schlagwort.")
            }
            TreeRows(node: root, sidebar: self)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    /// One folder with its subfolders and notes, drawn recursively.
    private struct TreeRows: View {
        var node: NoteTree
        var sidebar: SidebarView

        var body: some View {
            ForEach(node.folders) { child in
                DisclosureGroup(isExpanded: sidebar.expansion(child.path)) {
                    TreeRows(node: child, sidebar: sidebar)
                } label: {
                    sidebar.folderLabel(child)
                }
            }
            ForEach(node.notes) { record in
                sidebar.noteRow(record)
            }
        }
    }

    fileprivate func expansion(_ key: String) -> Binding<Bool> {
        Binding(get: { model.library.isExpanded(key) }, set: { model.library.setExpanded(key, $0) })
    }

    fileprivate func folderLabel(_ node: NoteTree) -> some View {
        HStack {
            Label(Folders.name(of: node.path), systemImage: "folder")
                .lineLimit(1)
            Spacer()
            count(node.notes.count)
        }
        .contextMenu {
            Button("Textnotiz hier", systemImage: "doc.text") { model.createText(in: node.path) }
            Button("Stiftnotiz hier", systemImage: "pencil.tip") { model.createInk(data: InkDrawing.empty(), in: node.path) }
            Divider()
            Button("Neuer Unterordner", systemImage: "folder.badge.plus") { ask(.create(parent: node.path)) }
            Button("Umbenennen", systemImage: "pencil") { ask(.rename(node.path)) }
            Divider()
            Button("Ordner entfernen", systemImage: "folder.badge.minus", role: .destructive) { pendingRemoval = node.path }
        }
    }

    fileprivate func noteRow(_ record: NoteRecord) -> some View {
        let note = record.note
        return HStack(spacing: 6) {
            Image(systemName: note.kind == .ink ? "pencil.tip" : "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(Ink.muted)
                .frame(width: 16)
            Text(note.displayTitle)
                .font(.system(size: 13, design: .serif))
                .lineLimit(1)
            Spacer(minLength: 4)
            if record.conflict {
                Text("Konflikt")
                    .font(.system(size: 10))
                    .foregroundStyle(Ink.accent)
            }
            if note.favorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Ink.accent)
                    .accessibilityLabel("Favorit")
            }
        }
        .tag(note.id)
        .swipeActions(edge: .trailing) { trailingSwipe(record) }
        .swipeActions(edge: .leading) { leadingSwipe(record) }
        .contextMenu { menu(for: record) }
    }

    private func count(_ value: Int) -> some View {
        Text(value > 0 ? "\(value)" : "")
            .font(.system(size: 11))
            .foregroundStyle(Ink.muted)
            .monospacedDigit()
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Ink.muted)
            .listRowBackground(Color.clear)
    }

    // MARK: Flat lists: search results, favorites, trash

    private func flatList(title: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.muted)
                    Spacer()
                    if model.section == .trash {
                        Button("Leeren") { confirmEmptyTrash = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(model.library.listing.trashCount == 0 ? Ink.muted : Ink.accent)
                            .disabled(model.library.listing.trashCount == 0)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
            List(selection: Bindable(model).selectedID) {
                if model.listed.isEmpty {
                    hint(emptyText)
                }
                ForEach(model.listed) { item in
                    NoteRow(item: item)
                        .tag(item.id)
                        .swipeActions(edge: .trailing) { trailingSwipe(item.record) }
                        .swipeActions(edge: .leading) { leadingSwipe(item.record) }
                        .contextMenu { menu(for: item.record) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyText: String {
        if isSearching { return "Nichts gefunden." }
        switch model.section {
        case .notes: return "Noch keine Notizen."
        case .favorites: return "Noch keine Favoriten."
        case .trash: return "Der Papierkorb ist leer."
        }
    }

    @ViewBuilder
    private func trailingSwipe(_ record: NoteRecord) -> some View {
        if record.note.deletedAt == nil {
            Button("Löschen", systemImage: "trash", role: .destructive) { pendingDelete = record.id }
        } else {
            Button("Endgültig", systemImage: "trash.slash", role: .destructive) { model.purge(id: record.id) }
        }
    }

    @ViewBuilder
    private func leadingSwipe(_ record: NoteRecord) -> some View {
        if record.note.deletedAt == nil {
            Button(record.note.favorite ? "Kein Favorit" : "Favorit", systemImage: record.note.favorite ? "star.slash" : "star") {
                model.library.toggleFavorite(id: record.id)
            }
            .tint(Ink.accent)
        } else {
            Button("Zurück", systemImage: "arrow.uturn.backward") { model.library.restore(id: record.id) }
                .tint(Ink.accent)
        }
    }

    @ViewBuilder
    private func menu(for record: NoteRecord) -> some View {
        if record.note.deletedAt == nil {
            Button(record.note.favorite ? "Aus Favoriten entfernen" : "Zu Favoriten", systemImage: record.note.favorite ? "star.slash" : "star") {
                model.library.toggleFavorite(id: record.id)
            }
            Divider()
            Button("In den Papierkorb", systemImage: "trash", role: .destructive) { pendingDelete = record.id }
        } else {
            Button("Wiederherstellen", systemImage: "arrow.uturn.backward") { model.library.restore(id: record.id) }
            Button("Endgültig löschen", systemImage: "trash.slash", role: .destructive) { model.purge(id: record.id) }
        }
    }

    // MARK: Footer

    private func footerButton(_ symbol: String, _ section: LibrarySection, label: String, count: Int = 0) -> some View {
        let active = model.section == section
        return Button {
            model.section = active ? .notes : section
        } label: {
            HStack(spacing: 3) {
                Image(systemName: active ? "\(symbol).fill" : symbol)
                    .font(.system(size: 14))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(active ? Ink.accent : Ink.muted)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isSyncEnabled ? "arrow.triangle.2.circlepath" : "internaldrive")
                .font(.system(size: 11))
                .foregroundStyle(Ink.muted)
            Text(model.status.isEmpty ? syncLabel : model.status)
                .font(.system(size: 11))
                .foregroundStyle(Ink.muted)
                .lineLimit(1)
            Spacer(minLength: 8)
            footerButton("star", .favorites, label: "Favoriten")
            footerButton("trash", .trash, label: "Papierkorb", count: model.library.listing.trashCount)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Einstellungen")
            .help("Workspaces und Server")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
    }

    private var syncLabel: String {
        guard let server = model.registry.server(of: model.registry.current) else { return StatusLine.localOnly }
        return ServerAddress.host(server.url)
    }

    // MARK: Folder prompt

    private enum FolderPrompt {
        case create(parent: String)
        case rename(String)

        var title: String {
            switch self {
            case .create(let parent): parent.isEmpty ? "Neuer Ordner" : "Neuer Ordner in \(Folders.name(of: parent))"
            case .rename: "Ordner umbenennen"
            }
        }

        var action: String {
            switch self {
            case .create: "Anlegen"
            case .rename: "Umbenennen"
            }
        }
    }

    private func ask(_ prompt: FolderPrompt) {
        if case .rename(let path) = prompt {
            folderName = Folders.name(of: path)
        } else {
            folderName = ""
        }
        folderPrompt = prompt
    }

    private func commitFolder() {
        switch folderPrompt {
        case .create(let parent):
            model.library.createFolder(named: folderName, in: parent)
        case .rename(let path):
            model.library.renameFolder(path, to: folderName)
        case nil:
            break
        }
        folderPrompt = nil
    }
}

struct WorkspaceSwitcher: View {
    @Environment(AppModel.self) private var model
    @Binding var newWorkspace: Bool
    @Binding var showSettings: Bool

    var body: some View {
        Menu {
            ForEach(model.registry.workspaces) { workspace in
                Button {
                    model.switchWorkspace(workspace.id)
                } label: {
                    if workspace.id == model.registry.current.id {
                        Label(workspace.name, systemImage: "checkmark")
                    } else {
                        WorkspaceMenuLabel(workspace: workspace)
                    }
                }
            }
            Divider()
            Button("Workspace anlegen …", systemImage: "plus") { newWorkspace = true }
            Button("Workspaces verwalten …", systemImage: "gearshape") { showSettings = true }
        } label: {
            HStack(spacing: 10) {
                WorkspaceIcon(workspace: model.registry.current, size: 20)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(model.registry.current.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.muted)
            }
            .foregroundStyle(Ink.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .inkSurface(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Workspace: \(model.registry.current.name)")
    }
}
