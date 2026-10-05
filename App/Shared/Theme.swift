import SwiftUI

/// The palette follows the mark: anthracite and greys, one quiet blue as accent. No warm tones.
enum Ink {
    static let paper = Color(red: 0.992, green: 0.992, blue: 0.988)
    static let deskTop = Color(red: 0.965, green: 0.966, blue: 0.970)
    static let deskBottom = Color(red: 0.925, green: 0.932, blue: 0.942)
    static let ink = Color(red: 0.11, green: 0.115, blue: 0.125)
    static let muted = Color(red: 0.42, green: 0.44, blue: 0.47)
    static let accent = Color(red: 0.24, green: 0.435, blue: 0.66)
    static let wordmark = Color(red: 0.353, green: 0.380, blue: 0.424)
    static let mark = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let markLight = Color(red: 0.55, green: 0.57, blue: 0.60)
    /// The edge of paper on paper. White alone vanishes on the sheet, so a trace of ink joins it.
    static let hairline = Color(red: 0.11, green: 0.115, blue: 0.125).opacity(0.09)

    static let serif = Font.system(.body, design: .serif)

    static var desk: LinearGradient {
        LinearGradient(colors: [deskTop, deskBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Device {
    /// True on an iPhone. Layout follows the width; only input that depends on the hardware asks this. See ADR 0026.
    @MainActor static var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}

extension View {
    /// A sheet's minimum size on the Mac. On iOS the system sizes sheets, and a fixed minimum would overflow an iPhone.
    @ViewBuilder
    func macSheetSize(minWidth: CGFloat, minHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, minHeight: minHeight)
        #else
        self
        #endif
    }

    /// True when the view has little width: an iPhone, or a narrow iPad window.
    func compactWidth(_ isCompact: Binding<Bool>) -> some View {
        modifier(CompactWidthReader(isCompact: isCompact))
    }
}

private struct CompactWidthReader: ViewModifier {
    @Binding var isCompact: Bool
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .onAppear { isCompact = sizeClass == .compact }
            .onChange(of: sizeClass) { _, next in isCompact = next == .compact }
        #else
        content
        #endif
    }
}

/// Everything that lies on the sheet is paper too: opaque, a hairline, a soft shadow. See ADR 0029.
extension View {
    func inkDesk() -> some View {
        background {
            Ink.desk.ignoresSafeArea()
        }
    }

    /// A sheet of paper on the desk. Website `.sheet`: radius 22, shadow 0/12/40 at 7 %.
    func inkPaper(radius: CGFloat = 22) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Ink.paper)
                .shadow(color: Color.black.opacity(0.07), radius: 20, y: 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        }
    }

    /// A floating surface: menus, bars, banners. Website header: radius 18, shadow 0/8/24.
    func inkSurface<S: InsettableShape>(in shape: S) -> some View {
        background {
            shape
                .fill(Ink.paper)
                .shadow(color: Color.black.opacity(0.07), radius: 12, y: 6)
        }
        .overlay {
            shape.strokeBorder(Ink.hairline, lineWidth: 1)
        }
    }

    func inkPanel(radius: CGFloat = 16) -> some View {
        inkSurface(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A secondary button: paper with a hairline. Website `.button`.
    func inkButton() -> some View {
        buttonStyle(InkButtonStyle(prominent: false))
    }

    /// The main action: anthracite with paper text. Website `.button.primary`.
    func inkPrimaryButton() -> some View {
        buttonStyle(InkButtonStyle(prominent: true))
    }

    /// Pen tools are anthracite like the ink, the active one filled. The blue accent stays for selection.
    func inkToolButton(isActive: Bool) -> some View {
        buttonStyle(InkToolButtonStyle(isActive: isActive))
    }
}

struct InkButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? Ink.paper : Ink.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(prominent ? Ink.ink : Ink.paper)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Ink.hairline, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct InkToolButtonStyle: ButtonStyle {
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isActive ? Ink.paper : Ink.ink)
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Ink.ink : (configuration.isPressed ? Ink.ink.opacity(0.08) : Color.clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The mark is a drawn `#`: two dark horizontals, a dark right vertical and a
/// lighter left vertical behind them. No extra slash. Strokes taper like a brush.
struct InkhashMark: View {
    var body: some View {
        Canvas { context, size in
            for stroke in Self.strokes {
                // Filled one by one: overlapping caps must not cancel out the body.
                for part in stroke.parts(in: size) {
                    context.fill(part, with: .color(stroke.color))
                }
            }
        }
        .accessibilityLabel("inkhash")
    }

    private struct Stroke {
        var from: CGPoint
        var to: CGPoint
        var width: CGFloat
        var color: Color

        /// A filled outline with round ends that thins toward its end, like a pen lifting off.
        func parts(in size: CGSize) -> [Path] {
            let a = CGPoint(x: from.x * size.width, y: from.y * size.height)
            let b = CGPoint(x: to.x * size.width, y: to.y * size.height)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = max(hypot(dx, dy), 0.001)
            let normal = CGPoint(x: -dy / length, y: dx / length)
            let maxHalf = max(0.6, width * size.width / 2)
            let steps = 64
            var left: [CGPoint] = []
            var right: [CGPoint] = []
            func half(_ t: CGFloat) -> CGFloat {
                // Full width through most of the stroke, a short attack and a longer lift-off.
                let attack = sin(min(1, t / 0.18) * .pi / 2)
                let release = sin(min(1, (1 - t) / 0.45) * .pi / 2)
                return maxHalf * (0.55 + 0.45 * attack) * (0.22 + 0.78 * release)
            }
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let h = half(t)
                let center = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
                left.append(CGPoint(x: center.x + normal.x * h, y: center.y + normal.y * h))
                right.append(CGPoint(x: center.x - normal.x * h, y: center.y - normal.y * h))
            }
            var path = Path()
            path.addLines(left + right.reversed())
            path.closeSubpath()
            let caps = [(a, half(0)), (b, half(1))].map { point, h in
                Path(ellipseIn: CGRect(x: point.x - h, y: point.y - h, width: h * 2, height: h * 2))
            }
            return [path] + caps
        }
    }

    private static let strokes: [Stroke] = [
        Stroke(from: CGPoint(x: 0.40, y: 0.05), to: CGPoint(x: 0.19, y: 0.95), width: 0.085, color: Ink.markLight),
        Stroke(from: CGPoint(x: 0.12, y: 0.40), to: CGPoint(x: 0.96, y: 0.29), width: 0.09, color: Ink.mark),
        Stroke(from: CGPoint(x: 0.03, y: 0.67), to: CGPoint(x: 0.88, y: 0.57), width: 0.09, color: Ink.mark),
        Stroke(from: CGPoint(x: 0.70, y: 0.03), to: CGPoint(x: 0.43, y: 0.93), width: 0.095, color: Ink.mark),
    ]
}

struct InkhashLogo: View {
    enum Axis {
        case inline
        case stacked
    }

    var axis: Axis = .inline
    var markSide: CGFloat = 22
    var wordSize: CGFloat = 17

    var body: some View {
        switch axis {
        case .inline:
            HStack(alignment: .center, spacing: markSide * 0.28) {
                mark
                word
            }
        case .stacked:
            VStack(spacing: markSide * 0.16) {
                mark
                word
            }
        }
    }

    private var mark: some View {
        InkhashMark()
            .frame(width: markSide, height: markSide)
            .accessibilityHidden(true)
    }

    private var word: some View {
        Text("inkhash")
            .font(.system(size: wordSize, weight: .semibold))
            .tracking(-0.4)
            .foregroundStyle(Ink.wordmark)
    }
}
