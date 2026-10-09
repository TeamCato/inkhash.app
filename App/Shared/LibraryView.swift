import InkhashCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    /// The tree is the way into the notes (ADR 0022); an open note gets the whole iPad (ADR 0030).
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var windowWidth: CGFloat = 1200

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(showSettings: $showSettings)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 440)
        } detail: {
            detail
        }
        .splitStyle(floating: sidebarFloats)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        .onChange(of: model.selectedID) { _, _ in placeSidebar() }
        .onAppear { placeSidebar() }
        .hidingWindowTitle()
        .inkDesk()
        .preferredColorScheme(.light)
        .tint(Ink.accent)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear { Task { await model.sync() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.sync() } }
        }
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
        if !showsNote {
            columns = .all
        } else if sidebarFloats {
            columns = .detailOnly
        }
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
        } else {
            VStack(spacing: 18) {
                InkhashLogo(axis: .stacked, markSide: 88, wordSize: 34)
                Text(model.isSyncEnabled
                    ? "Text auf dem Mac, Stift auf dem iPad.\nAbgeglichen über deinen Server."
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
                        .font(.system(size: 14, design: .serif))
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

    private var note: Note { item.record.note }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: note.kind == .ink ? "pencil.tip" : "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(Ink.muted)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.displayTitle)
                        .font(.system(size: 14, design: .serif))
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
                        .font(.system(size: 12))
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
                .font(.system(size: 11))
                .foregroundStyle(Ink.muted)
            }
        }
        .padding(.vertical, 3)
    }

    private func relative(_ iso: String) -> String {
        guard let date = InkhashTime.date(from: iso) else { return iso }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ExpiredSessionBanner: View {
    @Environment(AppModel.self) private var model
    var server: ServerEntry
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Die Anmeldung bei \(ServerAddress.host(server.url)) ist abgelaufen. Die Notizen bleiben auf diesem Gerät, abgeglichen wird erst nach dem Anmelden.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Anmelden") { showSettings = true }
                    .inkButton()
                Button("Später") { model.sessions.dismissExpiredNotice(server.id) }
                    .inkButton()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
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
