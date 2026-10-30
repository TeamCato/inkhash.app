import InkhashCore
import SwiftUI
import UniformTypeIdentifiers
import KennelKitUI

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
    /// A note written to a file, waiting for the person to pick where it goes. See ADR 0051.
    @State private var exported: ExportedFile?
    /// The vault, opened from a locked encrypted workspace (ADR 0082).
    @State private var vaultSheet: VaultSheet?

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                WorkspaceSwitcher(newWorkspace: $newWorkspace, showSettings: $showSettings)
                newMenu
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 8)
            searchField
            if model.overview.state.isLocked(model.registry.current.name) {
                lockedHint
            }
            if model.tagFilter != nil {
                tagSuggestions
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
        .sheet(item: $vaultSheet) { VaultSheetView(sheet: $0) }
        .alert(folderPrompt?.title ?? "", isPresented: Binding(get: { folderPrompt != nil }, set: { if !$0 { folderPrompt = nil } })) {
            TextField("Name", text: $folderName)
            Button("Abbrechen", role: .cancel) { folderPrompt = nil }
            Button(folderPrompt?.action ?? "OK") { commitFolder() }
        }
        .fileExporter(
            isPresented: Binding(get: { exported != nil }, set: { if !$0 { exported = nil } }),
            document: exported,
            contentType: exported.map { UTType(filenameExtension: $0.url.pathExtension) ?? .data } ?? .data,
            defaultFilename: exported?.url.lastPathComponent
        ) { result in
            if case .failure = result { model.status = "Die Datei ließ sich nicht sichern." }
            exported = nil
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
        .padding(.horizontal, 10)
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
            Button("PDF, GoodNotes oder Sicherung importieren…", systemImage: "square.and.arrow.down") { model.importRequested = true }
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
        .fileImporter(isPresented: $model.importRequested, allowedContentTypes: [.pdf, .goodnotes, .zip]) { result in
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
            // One flat ForEach, not nested DisclosureGroups: those left stale rows on the Mac. See PITFALLS P-056.
            ForEach(root.rows(isExpanded: model.library.isExpanded)) { row in
                Group {
                    switch row.item {
                    case .folder(let node, let expanded): folderRow(node, expanded: expanded)
                    case .note(let record, let expanded): noteRow(record, expanded: expanded)
                    }
                }
                .padding(.leading, CGFloat(row.depth) * TreeGuides.indent)
                .sidebarRow(selected: isSelected(row.item), depth: row.depth)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 34)
    }

    private func isSelected(_ item: TreeRow.Item) -> Bool {
        if case .note(let record, _) = item { return record.id == model.selectedID }
        return false
    }

    /// Room for the disclosure chevron.
    private func chevronSlot(_ expanded: Bool?) -> some View {
        Group {
            if let expanded {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.muted)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
        }
        .frame(width: 12)
    }

    private func folderRow(_ node: NoteTree, expanded: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.library.setExpanded(node.path, !expanded)
            }
        } label: {
            HStack(spacing: 8) {
                chevronSlot(expanded)
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.muted)
                    .frame(width: 20)
                Text(Folders.name(of: node.path))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                Spacer()
                count(node.noteCount)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "aufgeklappt" : "zugeklappt")
        .contextMenu {
            Button("Textnotiz hier", systemImage: "doc.text") { model.createText(in: node.path) }
            Button("Stiftnotiz hier", systemImage: "pencil.tip") { model.createInk(data: InkDrawing.empty(), in: node.path) }
            Divider()
            Button("Neuer Unterordner", systemImage: "folder.badge.plus") { ask(.create(parent: node.path)) }
            Button("Umbenennen", systemImage: "pencil") { ask(.rename(node.path)) }
            Divider()
            Button("Ordner entfernen", systemImage: "folder.badge.minus", role: .destructive) { pendingRemoval = node.path }
        }
        .confirmationDialog(
            "Ordner entfernen?",
            isPresented: Binding(get: { pendingRemoval == node.path }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ordner entfernen", role: .destructive) {
                model.library.removeFolder(node.path)
                pendingRemoval = nil
            }
            Button("Abbrechen", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Die Notizen darin bleiben erhalten und rücken eine Ebene nach oben.")
        }
    }

    /// `expanded` is nil for a note without notes hanging below it. See ADR 0090.
    fileprivate func noteRow(_ record: NoteRecord, expanded: Bool? = nil) -> some View {
        let note = record.note
        let selected = model.selectedID == record.id
        // The kind icon stands where folders have their chevron; the guide lines show the nesting.
        return HStack(spacing: 8) {
            NoteKindIcon(kind: note.kind, selected: selected)
            Text(note.displayTitle)
                .font(.system(size: 15, weight: selected ? .medium : .regular))
                .foregroundStyle(Ink.ink)
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
            if let expanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.library.setExpanded(NoteTree.expansionKey(for: record.id), !expanded)
                    }
                } label: {
                    chevronSlot(expanded)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                // Borderless, so a tap folds the note instead of choosing it.
                .buttonStyle(.borderless)
                .accessibilityLabel(expanded ? "Eingebettete Notizen zuklappen" : "Eingebettete Notizen aufklappen")
            }
        }
        .tag(note.id)
        .swipeActions(edge: .trailing) { trailingSwipe(record) }
        .swipeActions(edge: .leading) { leadingSwipe(record) }
        .contextMenu { menu(for: record) }
        .modifier(deleteConfirmation(for: record.id))
    }

    private func count(_ value: Int) -> some View {
        Text(value > 0 ? "\(value)" : "")
            .font(.system(size: 12))
            .foregroundStyle(Ink.muted)
            .monospacedDigit()
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Ink.muted)
            .sidebarRow(selected: false)
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
                            .confirmationDialog("Papierkorb leeren?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
                                Button("Endgültig löschen", role: .destructive) { model.emptyTrash() }
                                Button("Abbrechen", role: .cancel) {}
                            } message: {
                                Text("Sie verschwinden auch auf deinen anderen Geräten mit diesem Workspace.")
                            }
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
                    NoteRow(item: item, selected: model.selectedID == item.id)
                        .tag(item.id)
                        .sidebarRow(selected: model.selectedID == item.id)
                        .swipeActions(edge: .trailing) { trailingSwipe(item.record) }
                        .swipeActions(edge: .leading) { leadingSwipe(item.record) }
                        .contextMenu { menu(for: item.record) }
                        .modifier(deleteConfirmation(for: item.id))
                }
            }
            .listStyle(.plain)
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

    /// Attached per row so the iPad popover points at the note, not the middle of the sidebar.
    private func deleteConfirmation(for id: UUID) -> DeleteConfirmation {
        DeleteConfirmation(
            isPresented: Binding(get: { pendingDelete == id }, set: { if !$0 { pendingDelete = nil } }),
            confirm: { model.delete(id: id); pendingDelete = nil }
        )
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
            if let shared = model.shared(record.id) {
                ShareLink(item: shared, preview: SharePreview(record.note.displayTitle)) {
                    Label("Teilen…", systemImage: "square.and.arrow.up")
                }
            }
            Button(record.note.kind == .ink ? "Als PDF exportieren…" : "Als Markdown exportieren…", systemImage: "arrow.down.doc") {
                exported = model.exportFile(for: record.id)
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

    /// Logo while all is well, the message in its place while one stands. See ADR 0056.
    /// Opens the task list on the sheet; it is no section of the sidebar. See ADR 0060.
    private var tasksButton: some View {
        let active = model.showsTasks && model.selectedID == nil
        return Button {
            model.toggleTasks()
        } label: {
            Image(systemName: active ? "checklist.checked" : "checklist")
                .font(.system(size: 14))
                .foregroundStyle(active ? Ink.accent : Ink.muted)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aufgaben")
        .help("Aufgaben")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if StatusLine.isRoutine(model.status) {
                InkhashLogo(markSide: 14, wordSize: 12)
                    .opacity(0.55)
                    .help(statusText)
                    .accessibilityLabel(statusText)
            } else {
                Text(model.status)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
                    .help(model.status)
            }
            Spacer(minLength: 8)
            KennelSyncSymbol()
            tasksButton
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
            .help("Einstellungen, Workspaces und Kennel")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
    }

    /// What the place symbol says on hover and to VoiceOver.
    private var statusText: String {
        if !model.status.isEmpty, model.status != StatusLine.localOnly { return model.status }
        guard let kennel = model.registry.server(of: model.registry.current) else { return StatusLine.localOnly }
        return "Abgeglichen mit \(ServerAddress.host(kennel.url))"
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

extension SidebarView {
    /// A locked encrypted workspace: its notes from Kennel come once the vault is open here (ADR 0082).
    var lockedHint: some View {
        HStack(spacing: 8) {
            Label(KennelSyncState.lockedHint, systemImage: "lock")
                .font(.caption)
                .foregroundStyle(Ink.muted)
            Spacer()
            Button("Freischalten …") { vaultSheet = model.vaultSheetToOpen }
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
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
                    WorkspaceMenuLabel(workspace: workspace, isCurrent: workspace.id == model.registry.current.id)
                }
            }
            // Kennel workspaces not here yet, one tap away (ADR 0085).
            let unlinked = model.isSyncEnabled ? model.overview.unlinked(in: model.registry.setup) : []
            if !unlinked.isEmpty {
                Section("Aus Kennel hinzufügen") {
                    ForEach(unlinked) { remote in
                        Button {
                            Task { await model.addFromKennel([remote]) }
                        } label: {
                            Label(remote.name + (remote.isSealed ? " · verschlüsselt" : ""), systemImage: remote.symbol ?? "tray")
                        }
                    }
                }
            }
            Divider()
            Button("Workspace anlegen …", systemImage: "plus") { newWorkspace = true }
            Button("Workspaces und Kennel …", systemImage: "gearshape") { showSettings = true }
        } label: {
            HStack(spacing: 10) {
                WorkspaceIcon(workspace: model.registry.current, size: 20)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20, height: 20)
                Text(model.registry.current.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if model.registry.current.link?.sealed == true {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.muted)
                        .accessibilityLabel("Verschlüsselt")
                }
                if model.kennel != nil {
                    KennelPlaceBadge(model.overview.place(of: model.registry.current), style: .icon)
                }
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

/// One hairline per enclosing folder, under that folder's chevron, so a folder's contents read as
/// belonging to it. See ADR 0056.
private struct TreeGuides: View {
    static let indent: CGFloat = 16
    /// Middle of the chevron slot at the start of each row.
    private static let offset: CGFloat = 6

    var depth: Int

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<depth, id: \.self) { level in
                Rectangle()
                    .fill(Ink.hairline)
                    .frame(width: 1)
                    .offset(x: CGFloat(level) * Self.indent + Self.offset)
            }
        }
        .frame(maxHeight: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// Pen or text, in front of a note's title; blue while the note is chosen. See ADR 0056.
struct NoteKindIcon: View {
    var kind: NoteKind
    var selected: Bool

    var body: some View {
        Image(systemName: kind == .ink ? "pencil.tip" : "doc.text")
            .font(.system(size: 14))
            .foregroundStyle(selected ? Ink.accent : Ink.muted)
            .frame(width: 20)
            .accessibilityLabel(kind == .ink ? "Stiftnotiz" : "Textnotiz")
    }
}

/// A row of the sidebar's lists. The chosen note lies as a small sheet of paper on the desk, like
/// everything else above it; the system's grey highlight and separators do not show. See ADR 0056.
private struct SidebarRow: ViewModifier {
    var selected: Bool
    var depth: Int

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(alignment: .leading) {
                TreeGuides(depth: depth)
                    .padding(.leading, 10)
                    // Reaches into the row insets so the lines run on unbroken from row to row.
                    .padding(.vertical, -1)
            }
            .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
            .listRowSeparator(.hidden)
            .listRowBackground(
                Group {
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Ink.paper)
                            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Ink.hairline, lineWidth: 1)
                            )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 1)
                    } else {
                        Color.clear
                    }
                }
            )
    }
}

extension View {
    fileprivate func sidebarRow(selected: Bool, depth: Int = 0) -> some View {
        modifier(SidebarRow(selected: selected, depth: depth))
    }
}

private struct DeleteConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    var confirm: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Diese Notiz in den Papierkorb legen?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("In den Papierkorb", role: .destructive, action: confirm)
            Button("Abbrechen", role: .cancel) { isPresented = false }
        }
    }
}
