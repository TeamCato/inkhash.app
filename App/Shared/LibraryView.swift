import InkhashCore
import SwiftUI
import KennelKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    /// The tree is the way into the notes (ADR 0022); an open note gets the whole iPad (ADR 0030).
    @State private var columns = NavigationSplitViewVisibility.all
    /// On the iPhone the split view collapses to a stack; only this pushes the sheet over the tree.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar
    @State private var windowWidth: CGFloat = 1200

    var body: some View {
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            SidebarView(showSettings: $showSettings)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 440)
        } detail: {
            detail
        }
        .splitStyle(floating: sidebarFloats)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .onChange(of: model.selectedID) { _, _ in placeSidebar() }
        .onChange(of: model.showsTasks) { _, _ in placeSidebar() }
        .onChange(of: compactColumn) { _, column in
            // Going back on the iPhone closes the task list, so its button opens it again.
            if column == .sidebar, model.showsTasks, model.selectedID == nil { model.showsTasks = false }
        }
        .onAppear { placeSidebar() }
        .hidingWindowTitle()
        .inkDesk()
        .preferredColorScheme(.light)
        .tint(Ink.accent)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // inkhash://kennel/join?… opens „Mit Kennel verbinden“, filled in. See ADR 0071, 0077.
        .sheet(item: joinBinding) { link in
            InkhashConnectFlow(prefill: link)
        }
        .onAppear { Task { await model.sync() } }
        .onOpenURL { url in
            if model.open(url) { showSettings = false }
        }
        .handlesExternalEvents(preferring: [JoinLinks.scheme], allowing: ["*"])
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.sync() } }
        }
    }

    /// A join link the app was opened with. See ADR 0071.
    private var joinBinding: Binding<JoinLink?> {
        Binding(get: { model.pendingJoin }, set: { model.pendingJoin = $0 })
    }

    /// On the iPad, and in a narrow Mac window, the sidebar lies over the sheet instead of narrowing it,
    /// so a handwriting page keeps its scale when it comes and goes. See ADR 0030.
    private var sidebarFloats: Bool {
        #if os(iOS)
        true
        #else
        windowWidth < 900
        #endif
    }

    /// Opening a note hides the sidebar where it floats; without a note to show it comes back.
    private func placeSidebar() {
        let showsNote = model.selectedID.flatMap { model.library.record($0) }.map { $0.note.deletedAt == nil } ?? false
        if !showsNote, !model.showsTasks {
            columns = .all
        } else if sidebarFloats {
            columns = .detailOnly
        }
        // A note in the trash is shown too, so the stack follows any selection.
        compactColumn = model.selectedID != nil || model.showsTasks ? .detail : .sidebar
    }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedID, let record = model.library.record(id), record.note.deletedAt == nil {
            Group {
                switch record.note.kind {
                case .text:
                    TextNoteView(note: record.note, model: model)
                case .ink:
                    InkNoteView(note: record.note)
                }
            }
            .id("\(record.id.uuidString)-\(model.editorEpoch)")
        } else if let id = model.selectedID, let record = model.library.record(id) {
            TrashedNoteView(record: record)
        } else if model.showsTasks {
            TaskListView()
        } else {
            VStack(spacing: 18) {
                InkhashLogo(axis: .stacked, markSide: 88, wordSize: 34)
                Text(model.isSyncEnabled
                    ? "Text auf dem Mac, Stift auf dem iPad.\nAbgeglichen über deinen Kennel."
                    : "Text auf dem Mac, Stift auf dem iPad.\nAlles bleibt auf diesem Gerät.")
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("")
        }
    }
}

/// A note in the trash is shown, not edited. Restoring brings it back as it was.
struct TrashedNoteView: View {
    @Environment(AppModel.self) private var model
    var record: NoteRecord

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Ink.muted)
            Text(record.note.displayTitle)
                .font(.system(size: 22, design: .serif))
            Text("Liegt im Papierkorb.")
                .foregroundStyle(Ink.muted)
            if record.conflict {
                // Deleted here, changed elsewhere meanwhile: neither side wins on its own. See ADR 0005.
                VStack(spacing: 8) {
                    Text("Auf einem anderen Gerät wurde sie inzwischen geändert.")
                        .font(.system(size: 14))
                    HStack {
                        Button("Trotzdem löschen") { model.resolveConflict(id: record.id, choice: .mine) }
                            .inkButton()
                        Button("Geänderte Fassung holen") { model.resolveConflict(id: record.id, choice: .server) }
                            .inkButton()
                    }
                }
                .padding(14)
                .inkSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack {
                Button("Wiederherstellen") { model.library.restore(id: record.id) }
                    .inkButton()
                Button("Endgültig löschen", role: .destructive) { model.purge(id: record.id) }
                    .inkButton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper)
    }
}

/// A note in a flat list: search results, favorites, trash. Shows where it lies, since the tree does not.
struct NoteRow: View {
    var item: ListedNote
    var selected = false

    private var note: Note { item.record.note }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NoteKindIcon(kind: note.kind, selected: selected)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.displayTitle)
                        .font(.system(size: 15, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if item.record.conflict {
                        Text("Konflikt")
                            .font(.caption)
                            .foregroundStyle(Ink.accent)
                    }
                    if note.favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.accent)
                            .accessibilityLabel("Favorit")
                    }
                }
                if let snippet = item.snippet {
                    Text(snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.muted)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(relative(note.deletedAt ?? note.updatedAt))
                    if !note.folder.isEmpty {
                        Text(Folders.display(note.folder))
                            .lineLimit(1)
                    }
                    if !note.tags.isEmpty, item.snippet == nil {
                        Text(note.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                            .foregroundStyle(Ink.accent)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Ink.muted)
            }
        }
    }

    private func relative(_ iso: String) -> String {
        guard let date = InkhashTime.date(from: iso) else { return iso }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension View {
    /// The logo sits in the sidebar and the title on the sheet. The window title would repeat one of them.
    @ViewBuilder
    func hidingWindowTitle() -> some View {
        #if os(macOS)
        if #available(macOS 15, *) {
            toolbar(removing: .title)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

private extension View {
    /// Prominent detail lets the sidebar float over the sheet; balanced shares the width with it.
    @ViewBuilder
    func splitStyle(floating: Bool) -> some View {
        if floating {
            navigationSplitViewStyle(.prominentDetail)
        } else {
            navigationSplitViewStyle(.balanced)
        }
    }
}
