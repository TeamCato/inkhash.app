import InkhashCore
import SwiftUI
import UniformTypeIdentifiers

/// All pages of a handwritten note as thumbnails: tap to open, drag to move, context menu to move
/// by one or delete. See ADR 0042.
struct PageOverview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var noteID: UUID
    var current: UUID?
    var open: (UUID) -> Void

    /// The order while dragging; written to the note when the drag ends.
    @State private var order: [UUID] = []
    @State private var dragging: UUID?
    @State private var pendingDelete: UUID?

    var body: some View {
        let note = model.library.record(noteID)?.note
        let pages = note?.pages ?? []
        let byID = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        let paper = note?.shownPaper ?? .standard
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 190), spacing: 20)], spacing: 24) {
                    ForEach(Array(order.enumerated()), id: \.element) { index, id in
                        if let page = byID[id] {
                            tile(page, number: index + 1, paper: paper, count: order.count)
                        }
                    }
                }
                .padding(24)
            }
            // A drop between the tiles still ends the drag.
            .onDrop(of: [UTType.text], isTargeted: nil) { _ in
                commit()
                return true
            }
            .background(Ink.desk.ignoresSafeArea())
            .navigationTitle("Seiten")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 480)
        #endif
        .onAppear { order = pages.map(\.id) }
        .onChange(of: pages.map(\.id)) { _, ids in
            if dragging == nil { order = ids }
        }
        .onDisappear { commit() }
    }

    private func tile(_ page: InkPage, number: Int, paper: Paper, count: Int) -> some View {
        VStack(spacing: 8) {
            PageThumbnail(page: page, paper: paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(page.id == current ? Ink.accent : Color.white, lineWidth: page.id == current ? 2.5 : 1)
                )
                .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
                .opacity(dragging == page.id ? 0.4 : 1)
            Text("\(number)")
                .font(.system(size: 13, weight: page.id == current ? .semibold : .regular))
                .foregroundStyle(page.id == current ? Ink.ink : Ink.muted)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            open(page.id)
            dismiss()
        }
        .onDrag {
            dragging = page.id
            return NSItemProvider(object: page.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: PageDrop(target: page.id, order: $order, dragging: $dragging, commit: commit))
        .contextMenu {
            Button { model.library.movePage(noteID: noteID, pageID: page.id, by: -1) } label: {
                Label("Nach vorn", systemImage: "arrow.left")
            }
            .disabled(number == 1)
            Button { model.library.movePage(noteID: noteID, pageID: page.id, by: 1) } label: {
                Label("Nach hinten", systemImage: "arrow.right")
            }
            .disabled(number == count)
            Divider()
            Button(role: .destructive) { pendingDelete = page.id } label: {
                Label("Seite löschen", systemImage: "trash")
            }
            .disabled(count < 2)
        }
        .confirmationDialog(
            "Seite löschen?",
            isPresented: Binding(get: { pendingDelete == page.id }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Seite löschen", role: .destructive) {
                model.library.deletePage(noteID: noteID, pageID: page.id)
                pendingDelete = nil
            }
        } message: {
            Text("Die Seite verschwindet aus der Notiz. Ausschnitte daraus zeigen danach nichts mehr.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Seite \(number)")
        .accessibilityAddTraits(page.id == current ? [.isButton, .isSelected] : .isButton)
    }

    private func commit() {
        dragging = nil
        model.library.reorderPages(noteID: noteID, order: order)
    }
}

/// Moves the dragged page to where the pointer is, so the grid shows the new order while dragging.
private struct PageDrop: DropDelegate {
    var target: UUID
    @Binding var order: [UUID]
    @Binding var dragging: UUID?
    var commit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = order.firstIndex(of: dragging), let to = order.firstIndex(of: target) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        commit()
        return true
    }
}

/// The top of a page in its paper, at the proportions of a standard page.
struct PageThumbnail: View {
    @Environment(AppModel.self) private var model
    var page: InkPage
    var paper: Paper
    @State private var image: CGImage?

    private static let aspect = PageGeometry.height / PageGeometry.width

    var body: some View {
        Rectangle()
            .fill(paper.fill)
            .aspectRatio(1 / Self.aspect, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: "\(page.id)-\(page.blob)-\(paper.color)-\(paper.pattern.rawValue)") {
                let rect = CGRect(x: 0, y: 0, width: page.width, height: min(page.height, page.width * Self.aspect))
                image = PageImage.render(page, rect: rect, scale: 380 / page.width, paper: paper) { model.library.drawingData(for: $0) }
            }
    }
}
