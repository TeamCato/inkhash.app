import InkhashCore
import SwiftUI

/// Over a note in conflict: says so and opens the comparison. Nothing is decided here without
/// seeing both versions. See ADR 0049.
struct ConflictBanner: View {
    var noteID: UUID
    @State private var comparing = false

    var body: some View {
        HStack(spacing: 12) {
            Text("Auf dem Server liegt eine andere Fassung.")
                .font(.system(size: 14, design: .serif))
            Spacer(minLength: 8)
            Button("Vergleichen") { comparing = true }
                .inkButton()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 16)
        .sheet(isPresented: $comparing) {
            ConflictCompareView(noteID: noteID)
        }
    }
}

/// Both versions of a note side by side, lines only one of them has marked, and the choice:
/// keep mine, take the server's, or keep both. Narrow windows show one version at a time.
struct ConflictCompareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var noteID: UUID
    @State private var compact = false
    @State private var shown: LineDiff.Side = .left

    var body: some View {
        NavigationStack {
            Group {
                if let conflict = model.library.conflict(noteID) {
                    content(conflict)
                } else {
                    Text("Der Konflikt ist schon gelöst.")
                        .foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Ink.desk.ignoresSafeArea())
            .navigationTitle("Zwei Fassungen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Später") { dismiss() }
                }
            }
        }
        .compactWidth($compact)
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 540)
        #endif
    }

    private func content(_ conflict: NoteConflict) -> some View {
        let lines = Self.lines(conflict)
        return VStack(spacing: 0) {
            if compact {
                Picker("Fassung", selection: $shown) {
                    Text("Dieses Gerät").tag(LineDiff.Side.left)
                    Text("Server").tag(LineDiff.Side.right)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top], 16)
                VersionColumn(note: shown == .left ? conflict.local : conflict.server, side: shown, lines: lines)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VersionColumn(note: conflict.local, side: .left, lines: lines)
                    Divider()
                    VersionColumn(note: conflict.server, side: .right, lines: lines)
                }
            }
            Divider()
            choices(conflict)
        }
    }

    private func choices(_ conflict: NoteConflict) -> some View {
        HStack(spacing: 10) {
            ForEach(conflict.choices, id: \.self) { choice in
                Button(Self.label(choice, conflict: conflict)) {
                    model.resolveConflict(id: noteID, choice: choice)
                    dismiss()
                }
                .inkButton()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    static func label(_ choice: ConflictChoice, conflict: NoteConflict) -> String {
        switch choice {
        case .mine: conflict.local.deletedAt == nil ? "Meine behalten" : "Gelöscht lassen"
        case .server: conflict.server.deletedAt == nil ? "Server-Fassung nehmen" : "Auch hier löschen"
        case .both: "Beide behalten"
        }
    }

    /// Text notes compare their Markdown, ink notes their transcript: what a person can read.
    static func lines(_ conflict: NoteConflict) -> [LineDiff.Line] {
        LineDiff.compare(readable(conflict.local), readable(conflict.server))
    }

    private static func readable(_ note: Note) -> String {
        note.kind == .text ? (note.markdown ?? "") : (note.transcript ?? "")
    }
}

/// One version: where it comes from, when it changed, its title and path, then its content.
private struct VersionColumn: View {
    var note: Note
    var side: LineDiff.Side
    var lines: [LineDiff.Line]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if note.kind == .ink {
                    pages
                }
                if !shownLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if note.kind == .ink {
                            Text("Abschrift")
                                .font(.caption)
                                .foregroundStyle(Ink.muted)
                        }
                        ForEach(Array(shownLines.enumerated()), id: \.offset) { _, line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: 14, design: .serif))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(line.side == .both ? Color.clear : Ink.accent.opacity(0.12))
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(note.shownPaper.fill)
    }

    private var shownLines: [LineDiff.Line] {
        lines.filter { $0.side == .both || $0.side == side }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(side == .left ? "Auf diesem Gerät" : "Auf dem Server")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.muted)
            Text(note.displayTitle)
                .font(.system(size: 20, design: .serif))
            if !note.folder.isEmpty {
                Text(Folders.display(note.folder))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.muted)
            }
            HStack(spacing: 8) {
                if let date = InkhashTime.date(from: note.updatedAt) {
                    Text("Geändert \(date.formatted(date: .abbreviated, time: .shortened))")
                }
                if note.deletedAt != nil {
                    Text("Gelöscht")
                        .foregroundStyle(Ink.accent)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Ink.muted)
        }
    }

    private var pages: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)], spacing: 12) {
            ForEach(Array((note.pages ?? []).enumerated()), id: \.offset) { _, page in
                PageThumbnail(page: page, paper: note.shownPaper)
                    .shadow(color: .black.opacity(0.07), radius: 6, y: 2)
            }
        }
    }
}
