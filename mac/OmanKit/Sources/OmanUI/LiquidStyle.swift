import AppKit
import SwiftUI

enum Liquid {
    static let morph = Animation.smooth(duration: 0.28)
    static let press = Animation.easeOut(duration: 0.12)
    static let accent = Color(red: 0.40, green: 0.34, blue: 1.0)
    static let iridescence: [Color] = [
        Color(red: 0.40, green: 0.34, blue: 1.0),
        Color(red: 0.82, green: 0.32, blue: 0.96),
        Color(red: 1.0, green: 0.42, blue: 0.56),
        Color(red: 1.0, green: 0.68, blue: 0.36),
        Color(red: 0.30, green: 0.82, blue: 0.96),
        Color(red: 0.40, green: 0.34, blue: 1.0),
    ]
}

extension View {
    /// Apple's Writing Tools put a floating button beside selected text in OmanAI's own windows,
    /// where it covered the panel's Back button and took its clicks.
    @ViewBuilder
    func withoutSystemWritingTools() -> some View {
        if #available(macOS 15.0, *) {
            writingToolsBehavior(.disabled)
        } else {
            self
        }
    }
}

extension EnvironmentValues {
    @Entry var liquidSpace: Namespace.ID?
    @Entry var panelIsFloating = false
    /// Turned off for Settings, which has no animation at all.
    @Entry var liquidMotion = true
}

/// Which glass a shape gets. Kept apart from the view so the rule can be tested.
struct LiquidGlassChoice: Equatable {
    let isInteractive: Bool

    init(wantsInteraction: Bool, hasMotion: Bool) {
        // Interactive glass lights up and flexes, and Settings has no motion at all.
        isInteractive = wantsInteraction && hasMotion
    }
}

/// Moves the window when dragged. Placed behind controls, so they keep working.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The centre line of the corner grip, concentric with the corner of the tile.
private struct CornerArc: Shape {
    let radius: CGFloat
    let leadIn: CGFloat
    /// Distance from the top and right of the frame to the line.
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.maxX - inset - radius, y: rect.minY + inset + radius)
        var path = Path()
        path.move(to: CGPoint(x: center.x - leadIn, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
        path.addRelativeArc(center: center, radius: radius, startAngle: .degrees(-90), delta: .degrees(90))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y + leadIn))
        return path
    }
}

private struct ArcBand: Shape {
    let arc: CornerArc
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        arc.path(in: rect).strokedPath(StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// A dark curve with a thin glass border, wrapped around the top-right corner of the panel.
struct PanelCornerHandle: View {
    private static let thickness = PanelMetrics.gripThickness
    private static let barThickness: CGFloat = 5
    private static let leadIn: CGFloat = 8
    private static let radius = PanelMetrics.tileRadius + PanelMetrics.gap + thickness / 2
    private static let arc = CornerArc(radius: radius, leadIn: leadIn, inset: thickness / 2)
    private static let band = ArcBand(arc: arc, width: thickness)

    static let side = thickness + radius + leadIn

    var body: some View {
        Self.arc
            .stroke(Color.primary.opacity(0.42), style: StrokeStyle(lineWidth: Self.barThickness, lineCap: .round))
            // A SwiftUI shape above the drag area takes the click and does nothing with it.
            .allowsHitTesting(false)
            .frame(width: Self.side, height: Self.side)
            .background(WindowDragArea())
            // Glass in a custom shape adds no alpha to the window, so without this a click goes to the app behind.
            .background(Self.band.fill(Color.white.opacity(0.02)))
            .liquidGlass(in: Self.band)
            .help("Drag to move")
    }
}

/// Lets neighbouring glass shapes flow into each other while they animate.
struct LiquidContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

private struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let id: String?
    let interactive: Bool
    @Environment(\.liquidSpace) private var space
    @Environment(\.liquidMotion) private var hasMotion

    private var choice: LiquidGlassChoice {
        LiquidGlassChoice(wantsInteraction: interactive, hasMotion: hasMotion)
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            glassed(content)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { if let tint { shape.fill(tint.opacity(0.4)).allowsHitTesting(false) } }
                .overlay { shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5).allowsHitTesting(false) }
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func glassed(_ view: some View) -> some View {
        if let id, let space {
            view.glassEffect(glass, in: shape).glassEffectID(id, in: space)
        } else {
            view.glassEffect(glass, in: shape)
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
        return choice.isInteractive ? glass.interactive() : glass
    }
}

extension View {
    /// `interactive` is for buttons: in the panel they get Apple's glass, which lights up under the pointer
    /// and flexes when pressed.
    func liquidGlass<S: Shape>(in shape: S, tint: Color? = nil, id: String? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint, id: id, interactive: interactive))
    }
}

private struct LiquidPressBody<Label: View>: View {
    let isPressed: Bool
    let label: Label
    @Environment(\.liquidMotion) private var hasMotion

    var body: some View {
        label
            .opacity(isPressed ? 0.7 : 1)
            .animation(hasMotion ? Liquid.press : nil, value: isPressed)
    }
}

struct LiquidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LiquidPressBody(isPressed: configuration.isPressed, label: configuration.label)
    }
}

private struct GlassPressBody<Label: View>: View {
    let isPressed: Bool
    let label: Label
    @Environment(\.liquidMotion) private var hasMotion

    var body: some View {
        // Where the glass is interactive it shows the press itself, so the label stays as it is.
        label.opacity(isPressed && !hasMotion ? 0.7 : 1)
    }
}

/// For buttons drawn on interactive glass.
struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassPressBody(isPressed: configuration.isPressed, label: configuration.label)
    }
}

/// A glass capsule button. In the panel it uses Apple's interactive glass; Settings keeps it still.
struct LiquidButton: View {
    let title: String
    var symbol: String?
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16)
                .frame(height: 36)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .contentShape(Capsule())
                .liquidGlass(in: Capsule(), tint: prominent ? Liquid.accent : nil, interactive: true)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(GlassPressStyle())
    }

    @ViewBuilder
    private var label: some View {
        if let symbol {
            Label(title, systemImage: symbol)
        } else {
            Text(title)
        }
    }
}

/// The moving iridescent edge shown while Claude is writing.
struct LiquidGlow<S: InsettableShape>: View {
    let shape: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let gradient = AngularGradient(
                colors: Liquid.iridescence,
                center: .center,
                angle: .degrees(seconds.truncatingRemainder(dividingBy: 3.2) / 3.2 * 360)
            )
            ZStack {
                shape.strokeBorder(gradient, lineWidth: 7).blur(radius: 9).opacity(0.75)
                shape.strokeBorder(gradient, lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}
