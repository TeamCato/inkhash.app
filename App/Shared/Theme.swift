import SwiftUI

/// The palette of the app family (ADR 0066): deep blue ink on warm paper, blue grey as accent,
/// sage for what went well, warm sand for what needs a look. The desk is paper beige like the icon.
enum Ink {
    static let paper = Color(red: 0.992, green: 0.984, blue: 0.969)
    static let deskTop = Color(red: 0.984, green: 0.973, blue: 0.945)
    static let deskBottom = Color(red: 0.953, green: 0.902, blue: 0.824)
    static let ink = Color(red: 0.059, green: 0.129, blue: 0.220)
    static let muted = Color(red: 0.404, green: 0.447, blue: 0.482)
    static let accent = Color(red: 0.306, green: 0.420, blue: 0.478)
    static let sage = Color(red: 0.486, green: 0.604, blue: 0.522)
    static let amber = Color(red: 0.914, green: 0.718, blue: 0.427)
    /// Amber dark enough to read as text on paper.
    static let warning = Color(red: 0.580, green: 0.388, blue: 0.165)
    /// The quiet half of the wordmark, `hash`. `ink` stands in `Ink.ink`.
    static let wordmark = Color(red: 0.235, green: 0.271, blue: 0.302)
    static let mark = Color(red: 0.118, green: 0.141, blue: 0.149)
    static let markLight = Color(red: 0.639, green: 0.557, blue: 0.478)
    /// The edge of paper on paper. White alone vanishes on the sheet, so a trace of ink joins it.
    static let hairline = Color(red: 0.059, green: 0.129, blue: 0.220).opacity(0.09)

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

    /// The main action: navy ink with paper text. Website `.button.primary`.
    func inkPrimaryButton() -> some View {
        buttonStyle(InkButtonStyle(prominent: true))
    }

    /// Pen tools are navy like the ink, the active one filled. The slate accent stays for selection.
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

/// The mark is a drawn `#`, traced from the brush strokes of the app icon: two dark horizontals rising to the right,
/// a dark right vertical and a lighter left vertical behind them. No extra slash. Strokes taper like a brush.
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
                return maxHalf * (0.55 + 0.45 * attack) * (0.34 + 0.66 * release)
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
        Stroke(from: CGPoint(x: 0.392, y: 0.154), to: CGPoint(x: 0.202, y: 0.928), width: 0.076, color: Ink.markLight),
        Stroke(from: CGPoint(x: 0.094, y: 0.586), to: CGPoint(x: 0.905, y: 0.268), width: 0.069, color: Ink.mark),
        Stroke(from: CGPoint(x: 0.094, y: 0.744), to: CGPoint(x: 0.862, y: 0.463), width: 0.069, color: Ink.mark),
        Stroke(from: CGPoint(x: 0.645, y: 0.03), to: CGPoint(x: 0.375, y: 0.97), width: 0.097, color: Ink.mark),
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
        // Like the icon family: `ink` in full ink, `hash` quieter.
        Text("\(Text("ink").foregroundColor(Ink.ink))hash")
            .foregroundColor(Ink.wordmark)
            .font(.system(size: wordSize, weight: .semibold))
            .tracking(-0.4)
            .accessibilityLabel("inkhash")
    }
}
