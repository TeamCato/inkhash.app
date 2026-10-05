import InkhashCore
import SwiftUI

/// What the page editor knows that the sheet around it shows: the selection, where the page is
/// scrolled to, and the requests the sheet sends back. See ADR 0028.
@MainActor
@Observable
final class InkEditorState {
    struct Selection: Equatable {
        var elementIDs: Set<UUID>
        var strokeCount: Int
        /// Page coordinates.
        var bounds: CGRect

        var isEmpty: Bool { elementIDs.isEmpty && strokeCount == 0 }
        var hasInk: Bool { strokeCount > 0 }
        var count: Int { elementIDs.count + strokeCount }
    }

    var selection: Selection?
    /// Scroll position of the page, in screen points. Badges follow it.
    var offset: CGPoint = .zero
    var maskDrawing: UUID?
    var linkPrompt = false

    @ObservationIgnored weak var controller: InkPageControlling?

    func clearSelection() {
        controller?.select(nil)
    }

    func deleteSelection() {
        controller?.deleteSelection()
    }

    func setLink(_ target: String?) {
        linkPrompt = false
        controller?.setLink(target)
    }

    func change(_ body: @escaping (inout PageElement) -> Void) {
        controller?.changeSelected(body)
    }

    func bringToFront(_ front: Bool) {
        controller?.restack(front: front)
    }

    func beginMaskDrawing() {
        guard let id = selection?.elementIDs.first else { return }
        maskDrawing = id
        controller?.setMaskDrawing(id)
    }

    func cancelMaskDrawing() {
        maskDrawing = nil
        controller?.setMaskDrawing(nil)
    }

    func insertImage(blob: String, size: CGSize) {
        controller?.insertImage(blob: blob, pixelSize: size)
    }

    /// An excerpt of another note in the middle of what is visible. See ADR 0037.
    func insertExcerpt(_ target: ExcerptTarget) {
        controller?.insertExcerpt(target)
    }
}

/// The page editor, as the sheet sees it.
@MainActor
protocol InkPageControlling: AnyObject {
    func select(_ ids: Set<UUID>?)
    func deleteSelection()
    func setLink(_ target: String?)
    func changeSelected(_ body: @escaping (inout PageElement) -> Void)
    func restack(front: Bool)
    func setMaskDrawing(_ id: UUID?)
    func insertImage(blob: String, pixelSize: CGSize)
    func insertExcerpt(_ target: ExcerptTarget)
}

/// Above the page while something is selected: what applies to it. One element gets its own
/// options; several things get link, delete and done. See ADR 0028.
struct InkSelectionBar: View {
    var state: InkEditorState
    var element: PageElement?
    var excluding: UUID?
    /// Puts the selection on the pasteboard as an excerpt for a text note. See ADR 0032.
    var copyExcerpt: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            if state.maskDrawing != nil {
                Image(systemName: "scribble")
                Text("Umriss um das Bild ziehen")
                    .font(.system(size: 13))
                Button("Abbrechen") { state.cancelMaskDrawing() }
                    .inkButton()
            } else {
                if let element {
                    options(for: element)
                } else if let selection = state.selection {
                    Text(selection.count == 1 ? "1 Teil" : "\(selection.count) Teile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.muted)
                        .padding(.horizontal, 6)
                }
                // An excerpt's link is its source; it is not changed here. See ADR 0035.
                if element?.kind != .excerpt {
                    barButton(currentLink == nil ? "link.badge.plus" : "link", "Verlinken") { state.linkPrompt = true }
                        .popover(isPresented: Binding(get: { state.linkPrompt }, set: { state.linkPrompt = $0 }), arrowEdge: .top) {
                            LinkEditor(current: currentLink, excluding: excluding) { state.setLink($0) }
                        }
                }
                if let copyExcerpt {
                    barButton("text.below.photo", "Als Ausschnitt kopieren", action: copyExcerpt)
                }
                if element != nil {
                    barButton("square.3.layers.3d.top.filled", "Nach vorn") { state.bringToFront(true) }
                    barButton("square.3.layers.3d.bottom.filled", "Nach hinten") { state.bringToFront(false) }
                }
                barButton("trash", "Löschen") { state.deleteSelection() }
                barButton("xmark", "Fertig") { state.clearSelection() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .inkPanel(radius: 16)
    }

    private var currentLink: String? { element?.link }

    @ViewBuilder
    private func options(for element: PageElement) -> some View {
        switch element.kind {
        case .image:
            Menu {
                Picker("Rahmen", selection: Binding(
                    get: { element.frame?.style ?? .none },
                    set: { style in state.change { $0.frame = style == .none ? nil : PageElement.Frame(style: style, color: $0.frame?.color ?? "#FFFFFF", width: $0.frame?.width ?? 12, shadow: $0.frame?.shadow ?? true) } }
                )) {
                    Text("Kein Rahmen").tag(PageElement.Frame.Style.none)
                    Text("Rahmen").tag(PageElement.Frame.Style.solid)
                    Text("Polaroid").tag(PageElement.Frame.Style.polaroid)
                }
                if let frame = element.frame, frame.style != .none {
                    Section("Farbe") {
                        ForEach(["#FFFFFF", "#1C1D20", "#FDFDFC", "#2F6FED", "#C44536"], id: \.self) { hex in
                            Button(Self.colorName(hex)) { state.change { $0.frame?.color = hex } }
                        }
                    }
                    Menu("Breite") {
                        ForEach([6.0, 12, 20, 28], id: \.self) { width in
                            Button("\(Int(width))") { state.change { $0.frame?.width = width } }
                        }
                    }
                }
                Toggle("Schatten", isOn: Binding(
                    get: { element.frame?.shadow ?? false },
                    set: { on in state.change { element in
                        var frame = element.frame ?? PageElement.Frame(style: .none, width: 0, shadow: false)
                        frame.shadow = on
                        element.frame = frame
                    } }
                ))
            } label: {
                barIcon("photo.artframe")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Rahmen")
            Menu {
                Button("Keine Maske") { state.change { $0.mask = nil } }
                Button("Kreis") { state.change { $0.mask = .init(kind: .circle) } }
                Button("Rechteck") { state.change { $0.mask = .init(kind: .rectangle) } }
                Button("Umriss zeichnen …") { state.beginMaskDrawing() }
            } label: {
                barIcon("crop")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Maske")
        case .shape:
            Menu {
                Section("Kontur") {
                    Button("Keine") { state.change { $0.stroke = nil } }
                    ForEach(InkToolState.inks + InkToolState.markers, id: \.self) { hex in
                        Button(Self.colorName(hex)) { state.change { $0.stroke = hex } }
                    }
                }
                Menu("Stärke") {
                    ForEach([1.5, 3, 6, 10], id: \.self) { width in
                        Button("\(width.formatted())") { state.change { $0.strokeWidth = width } }
                    }
                }
            } label: {
                barIcon("pencil.tip.crop.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Kontur")
            Menu {
                Button("Keine Füllung") { state.change { $0.fill = nil; $0.fillOpacity = nil } }
                ForEach(InkToolState.inks + InkToolState.markers, id: \.self) { hex in
                    Button(Self.colorName(hex)) { state.change { $0.fill = hex; $0.fillOpacity = $0.fillOpacity ?? 0.35 } }
                }
            } label: {
                barIcon("drop.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Füllung")
        case .tape:
            Menu {
                ForEach(InkToolState.tapes, id: \.self) { hex in
                    Button(Self.colorName(hex)) { state.change { $0.color = hex } }
                }
                Menu("Breite") {
                    ForEach([24.0, 40, 56, 72], id: \.self) { height in
                        Button("\(Int(height))") { state.change { $0.height = height } }
                    }
                }
            } label: {
                barIcon("paintpalette")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Tape")
        case .excerpt:
            Text("Ausschnitt")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, 6)
        case .link:
            Text("Linkfläche")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, 6)
        }
    }

    private func barButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { barIcon(symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .help(title)
    }

    private func barIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Ink.ink)
            .frame(width: 32, height: 30)
            .contentShape(Rectangle())
    }

    static func colorName(_ hex: String) -> String {
        [
            "#1C1D20": "Anthrazit", "#5C6370": "Grau", "#2F6FED": "Blau", "#1F7A4D": "Grün", "#C44536": "Rot",
            "#FFE433": "Gelb", "#FF8B38": "Orange", "#FF73B3": "Pink", "#4DB3FF": "Hellblau", "#66E666": "Hellgrün",
            "#FFFFFF": "Weiß", "#FDFDFC": "Papier", "#F0E6C7": "Krepp", "#FCFCF7": "Weiß", "#FDE68A": "Gelb",
            "#FBCFE8": "Rosa", "#BFDBFE": "Blau", "#BBF7D0": "Grün", "#E9D5FF": "Lila",
        ][hex] ?? hex
    }
}
