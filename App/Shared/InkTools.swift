import InkhashCore
import SwiftUI

#if os(iOS)
import PencilKit
import UIKit
#endif

enum InkPen: String, CaseIterable, Identifiable {
    case fountain
    case pen
    case monoline
    case marker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fountain: "Füller"
        case .pen: "Stift"
        case .monoline: "Strich"
        case .marker: "Marker"
        }
    }

    var symbol: String {
        switch self {
        case .fountain: "paintbrush.pointed"
        case .pen: "pencil.tip"
        case .monoline: "pencil.line"
        case .marker: "highlighter"
        }
    }

    var defaultWidth: Double {
        switch self {
        case .fountain: 5
        case .pen: 3
        case .monoline: 2.5
        case .marker: 18
        }
    }

    var widths: [Double] {
        self == .marker ? [12, 18, 28, 40] : [1.5, 3, 6, 10]
    }

    var defaultColor: String {
        self == .marker ? "#FFE433" : "#1C1D20"
    }

    #if os(iOS)
    var inkType: PKInkingTool.InkType {
        switch self {
        case .fountain: .fountainPen
        case .pen: .pen
        case .monoline: .monoline
        case .marker: .marker
        }
    }
    #endif
}

struct InkStrokeTool: Equatable {
    var pen: InkPen
    var erasing: Bool
    var pixelErase: Bool
    var colorHex: String
    var width: Double
}

/// What the page does with a touch. Drawing is PencilKit; the rest are page elements. See ADR 0028.
enum InkMode: String, Codable {
    case draw, shape, tape, select
}

enum ImageSource {
    case photos, files
    /// Part of another note, handwriting or text, shown on the page. See ADR 0037.
    case text
}

@MainActor
@Observable
final class InkToolState {
    var mode: InkMode
    var pen: InkPen
    var erasing: Bool
    var pixelErase: Bool
    var colors: [String: String]
    var widths: [String: Double]
    var eraserWidth: Double
    var fingerDraws: Bool
    var shapeForm: PageElement.ShapeForm
    var shapeFills: Bool
    var tapeColor: String
    var tapeWidth: Double
    /// Colors picked with the system picker, newest first, at most twelve.
    var customColors: [String]

    static let inks = ["#1C1D20", "#5C6370", "#2F6FED", "#1F7A4D", "#C44536"]
    static let markers = ["#FFE433", "#FF8B38", "#FF73B3", "#4DB3FF", "#66E666"]
    static let tapes = ["#F0E6C7", "#FCFCF7", "#FDE68A", "#FBCFE8", "#BFDBFE", "#BBF7D0", "#E9D5FF"]

    init() {
        let stored = UserDefaults.standard.data(forKey: Self.storageKey).flatMap {
            try? JSONDecoder().decode(Memory.self, from: $0)
        }
        let storedMode = stored?.mode.flatMap(InkMode.init(rawValue:)) ?? .draw
        // A new page starts writing, not selecting.
        mode = storedMode == .select ? .draw : storedMode
        pen = InkPen(rawValue: stored?.pen ?? "") ?? .pen
        erasing = stored?.erasing ?? false
        pixelErase = stored?.pixelErase ?? false
        colors = stored?.colors ?? [:]
        widths = stored?.widths ?? [:]
        eraserWidth = stored?.eraserWidth ?? 18
        fingerDraws = stored?.fingerDraws ?? false
        shapeForm = stored?.shapeForm.flatMap(PageElement.ShapeForm.init(rawValue:)) ?? .rect
        shapeFills = stored?.shapeFills ?? false
        tapeColor = stored?.tapeColor ?? ElementRenderer.defaultTape
        tapeWidth = stored?.tapeWidth ?? 40
        customColors = stored?.customColors ?? []
    }

    func color(for pen: InkPen) -> String {
        colors[pen.rawValue] ?? pen.defaultColor
    }

    func width(for pen: InkPen) -> Double {
        widths[pen.rawValue] ?? pen.defaultWidth
    }

    var shapeColor: String { colors["shape"] ?? "#1C1D20" }
    var shapeWidth: Double { widths["shape"] ?? 3 }

    /// The color the swatches show as chosen, for what is active now.
    var currentColor: String {
        switch mode {
        case .draw, .select: color(for: pen)
        case .shape: shapeColor
        case .tape: tapeColor
        }
    }

    var currentWidth: Double {
        switch mode {
        case .draw, .select: erasing ? eraserWidth : width(for: pen)
        case .shape: shapeWidth
        case .tape: tapeWidth
        }
    }

    var swatches: [String] {
        switch mode {
        case .tape: Self.tapes
        case .draw, .select: pen == .marker ? Self.markers + Array(Self.inks.prefix(1)) : Self.inks + Array(Self.markers.prefix(1))
        case .shape: Self.inks + Array(Self.markers.prefix(1))
        }
    }

    var widthPresets: [Double] {
        switch mode {
        case .draw, .select: erasing ? [10, 18, 28, 44] : pen.widths
        case .shape: [1.5, 3, 6, 10]
        case .tape: [24, 40, 56, 72]
        }
    }

    var showsColors: Bool { !(mode == .draw && erasing) && mode != .select }
    var showsWidths: Bool { mode != .select && !(mode == .draw && erasing && !pixelErase) }

    var strokeTool: InkStrokeTool {
        InkStrokeTool(
            pen: pen,
            erasing: erasing,
            pixelErase: pixelErase,
            colorHex: color(for: pen),
            width: erasing && pixelErase ? eraserWidth : width(for: pen)
        )
    }

    func choose(_ next: InkPen) {
        pen = next
        erasing = false
        mode = .draw
        store()
    }

    func chooseEraser() {
        erasing = true
        mode = .draw
        store()
    }

    func choose(_ next: InkMode) {
        mode = next
        store()
    }

    func pickColor(_ hex: String) {
        switch mode {
        case .draw, .select: colors[pen.rawValue] = hex
        case .shape: colors["shape"] = hex
        case .tape: tapeColor = hex
        }
        store()
    }

    /// A color from the system picker: used now and kept among the custom colors.
    func pickCustomColor(_ hex: String) {
        customColors.removeAll { $0 == hex }
        customColors.insert(hex, at: 0)
        customColors = Array(customColors.prefix(12))
        pickColor(hex)
    }

    func removeCustomColor(_ hex: String) {
        customColors.removeAll { $0 == hex }
        store()
    }

    func pickWidth(_ value: Double) {
        switch mode {
        case .draw, .select:
            if erasing { eraserWidth = value } else { widths[pen.rawValue] = value }
        case .shape: widths["shape"] = value
        case .tape: tapeWidth = value
        }
        store()
    }

    func pickEraser(pixel: Bool) {
        pixelErase = pixel
        store()
    }

    func pickShape(_ form: PageElement.ShapeForm) {
        shapeForm = form
        mode = .shape
        store()
    }

    func toggleShapeFill() {
        shapeFills.toggle()
        store()
    }

    func toggleFinger() {
        fingerDraws.toggle()
        store()
    }

    /// A new shape as the tools stand. Fill is the stroke color, light.
    func shapeElement(form: PageElement.ShapeForm, x: Double, y: Double, width: Double, height: Double, rotation: Double, z: Int) -> PageElement {
        PageElement(
            kind: .shape, x: x, y: y, width: width, height: height, rotation: rotation, z: z,
            shape: form, stroke: shapeColor, strokeWidth: shapeWidth,
            fill: shapeFills && form != .line ? shapeColor : nil, fillOpacity: shapeFills && form != .line ? 0.25 : nil
        )
    }

    private func store() {
        let memory = Memory(
            mode: mode.rawValue, pen: pen.rawValue, erasing: erasing, pixelErase: pixelErase, colors: colors,
            widths: widths, eraserWidth: eraserWidth, fingerDraws: fingerDraws, shapeForm: shapeForm.rawValue,
            shapeFills: shapeFills, tapeColor: tapeColor, tapeWidth: tapeWidth, customColors: customColors
        )
        if let data = try? JSONEncoder().encode(memory) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "inkhash.inkTools"

    private struct Memory: Codable {
        var mode: String?
        var pen: String
        var erasing: Bool
        var pixelErase: Bool
        var colors: [String: String]
        var widths: [String: Double]
        var eraserWidth: Double
        var fingerDraws: Bool
        var shapeForm: String?
        var shapeFills: Bool?
        var tapeColor: String?
        var tapeWidth: Double?
        var customColors: [String]?
    }
}

#if os(iOS)
/// The tools and their options in one strip at the edge, always open. Vertical at the left edge,
/// horizontal at the bottom on narrow screens. See ADR 0028.
struct InkToolRail: View {
    var tools: InkToolState
    var vertical: Bool
    var addImage: (ImageSource) -> Void

    var body: some View {
        Group {
            if vertical {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) { content }
                        .padding(.vertical, 10)
                        .frame(width: 52)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) { content }
                        .padding(.horizontal, 10)
                        .frame(height: 50)
                }
            }
        }
        .inkPanel(radius: 18)
    }

    @ViewBuilder
    private var content: some View {
        ForEach(InkPen.allCases) { pen in
            tool(pen.symbol, title: pen.title, active: tools.mode == .draw && !tools.erasing && tools.pen == pen,
                 swatch: Color(inkHex: tools.color(for: pen))) { tools.choose(pen) }
        }
        tool(tools.pixelErase ? "eraser.line.dashed" : "eraser", title: "Radierer", active: tools.mode == .draw && tools.erasing) {
            tools.chooseEraser()
        }
        shapeTool
        tool("rectangle.compress.vertical", title: "Tape", active: tools.mode == .tape, swatch: Color(inkHex: tools.tapeColor)) {
            tools.choose(.tape)
        }
        Menu {
            Button("Fotos", systemImage: "photo.on.rectangle") { addImage(.photos) }
            Button("Dateien", systemImage: "folder") { addImage(.files) }
            Divider()
            Button("Ausschnitt", systemImage: "text.quote") { addImage(.text) }
        } label: {
            icon("photo", swatch: nil)
        }
        .menuStyle(.button)
        .buttonStyle(InkToolButtonStyle(isActive: false))
        .menuIndicator(.hidden)
        .accessibilityLabel("Bild einfügen")
        tool("lasso", title: "Auswahl", active: tools.mode == .select) { tools.choose(.select) }

        separator
        modeOptions
        if tools.showsColors {
            ForEach(tools.swatches, id: \.self) { hex in
                ColorSwatch(hex: hex, selected: tools.currentColor == hex) { tools.pickColor(hex) }
            }
            ForEach(tools.customColors.filter { !tools.swatches.contains($0) }.prefix(6), id: \.self) { hex in
                ColorSwatch(hex: hex, selected: tools.currentColor == hex) { tools.pickColor(hex) }
                    .contextMenu {
                        Button("Farbe entfernen", systemImage: "trash", role: .destructive) { tools.removeCustomColor(hex) }
                    }
            }
            ColorPicker(
                "Eigene Farbe",
                selection: Binding(get: { Color(inkHex: tools.currentColor) }, set: { tools.pickCustomColor(UIColor($0).inkHex) }),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 30, height: 30)
        }
        if tools.showsWidths {
            separator
            ForEach(tools.widthPresets, id: \.self) { preset in
                Button {
                    tools.pickWidth(preset)
                } label: {
                    let side = tools.mode == .tape ? min(20, preset * 0.3) : min(18, 4 + preset * (tools.pen == .marker && tools.mode == .draw ? 0.35 : 1.2))
                    Group {
                        if tools.mode == .tape {
                            RoundedRectangle(cornerRadius: 2).frame(width: 18, height: side)
                        } else if tools.erasing {
                            Circle().strokeBorder(lineWidth: 1.5).frame(width: side, height: side)
                        } else {
                            Circle().frame(width: side, height: side)
                        }
                    }
                    .foregroundStyle(Ink.ink.opacity(abs(tools.currentWidth - preset) < 0.2 ? 0.9 : 0.28))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stärke")
            }
        }
        if !Device.isPhone {
            separator
            tool("hand.tap", title: "Mit dem Finger", active: tools.fingerDraws) { tools.toggleFinger() }
        }
    }

    @ViewBuilder
    private var modeOptions: some View {
        if tools.mode == .draw, tools.erasing {
            tool("scribble", title: "Ganze Striche", active: !tools.pixelErase) { tools.pickEraser(pixel: false) }
            tool("circle.dashed", title: "Pixel", active: tools.pixelErase) { tools.pickEraser(pixel: true) }
        } else if tools.mode == .shape {
            ForEach(PageElement.ShapeForm.allCases, id: \.self) { form in
                tool(Self.symbol(form), title: Self.title(form), active: tools.shapeForm == form) { tools.pickShape(form) }
            }
            tool(tools.shapeFills ? "circle.fill" : "circle", title: "Füllung", active: tools.shapeFills) { tools.toggleShapeFill() }
        } else if tools.mode == .select, !vertical {
            Text("Ziehen zum Auswählen")
                .font(.system(size: 11))
                .foregroundStyle(Ink.muted)
                .fixedSize()
                .padding(.horizontal, 6)
        }
    }

    private var shapeTool: some View {
        tool(Self.symbol(tools.shapeForm), title: "Form", active: tools.mode == .shape) { tools.choose(.shape) }
    }

    private var separator: some View {
        Group {
            if vertical {
                Rectangle().fill(Ink.hairline).frame(width: 28, height: 1).padding(.vertical, 4)
            } else {
                Rectangle().fill(Ink.hairline).frame(width: 1, height: 28).padding(.horizontal, 4)
            }
        }
    }

    private func tool(_ symbol: String, title: String, active: Bool, swatch: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(symbol, swatch: swatch) }
            .inkToolButton(isActive: active)
            .accessibilityLabel(title)
            .help(title)
    }

    private func icon(_ symbol: String, swatch: Color?) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
            if let swatch {
                Capsule().fill(swatch).frame(width: 16, height: 3)
            }
        }
        .frame(width: 30, height: swatch == nil ? 28 : 32)
    }

    static func symbol(_ form: PageElement.ShapeForm) -> String {
        switch form {
        case .line: "line.diagonal"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .triangle: "triangle"
        }
    }

    static func title(_ form: PageElement.ShapeForm) -> String {
        switch form {
        case .line: "Linie"
        case .rect: "Rechteck"
        case .ellipse: "Ellipse"
        case .triangle: "Dreieck"
        }
    }
}

struct ColorSwatch: View {
    var hex: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(inkHex: hex))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: 1))
                .overlay(Circle().strokeBorder(selected ? Ink.accent : .clear, lineWidth: 2).padding(-4))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Farbe")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension UIColor {
    /// "#RRGGBB", upper case like the server stores it.
    var inkHex: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func part(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", part(red), part(green), part(blue))
    }

    convenience init(inkHex: String) {
        var value: UInt64 = 0
        Scanner(string: String(inkHex.dropFirst())).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(inkHex: String) {
        self.init(uiColor: UIColor(inkHex: inkHex))
    }
}
#endif
