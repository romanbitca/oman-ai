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

extension EnvironmentValues {
    @Entry var liquidSpace: Namespace.ID?
    @Entry var panelIsFloating = false
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

private struct CornerArc: Shape {
    let radius: CGFloat
    let leadIn: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.maxX - radius, y: rect.minY + radius)
        var path = Path()
        path.move(to: CGPoint(x: center.x - leadIn, y: rect.minY))
        path.addLine(to: CGPoint(x: center.x, y: rect.minY))
        path.addRelativeArc(center: center, radius: radius, startAngle: .degrees(-90), delta: .degrees(90))
        path.addLine(to: CGPoint(x: rect.maxX, y: center.y + leadIn))
        return path
    }
}

/// A curved grip that follows the top-right corner of the panel, just outside it.
struct PanelCornerHandle: View {
    static let outset: CGFloat = 11
    static let hitWidth: CGFloat = 14
    /// How far the handle's frame reaches past the corner of the tile it wraps.
    static let reach = outset + hitWidth / 2

    private let arc = CornerArc(radius: PanelMetrics.tileRadius + outset, leadIn: 13)
    private let side = PanelMetrics.tileRadius + outset + 13
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Fully clear pixels let clicks fall through to the app behind, so the grip needs a trace of alpha.
            arc.stroke(Color.white.opacity(0.02), style: StrokeStyle(lineWidth: Self.hitWidth, lineCap: .round))
            arc.stroke(
                Color(nsColor: .systemGray).opacity(isHovering ? 1 : 0.7),
                style: StrokeStyle(lineWidth: 5, lineCap: .round)
            )
        }
        .frame(width: side, height: side)
        .padding(Self.hitWidth / 2)
        .background(WindowDragArea())
        .help("Drag to move")
        .onHover { hovering in
            withAnimation(Liquid.press) { isHovering = hovering }
        }
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
    @Environment(\.liquidSpace) private var space

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if let id, let space {
                content.glassEffect(glass, in: shape).glassEffectID(id, in: space)
            } else {
                content.glassEffect(glass, in: shape)
            }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { if let tint { shape.fill(tint.opacity(0.4)).allowsHitTesting(false) } }
                .overlay { shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5).allowsHitTesting(false) }
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        tint.map { Glass.regular.tint($0) } ?? Glass.regular
    }
}

extension View {
    func liquidGlass<S: Shape>(in shape: S, tint: Color? = nil, id: String? = nil) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint, id: id))
    }
}

struct LiquidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Liquid.press, value: configuration.isPressed)
    }
}

/// Drawn by hand because the system glass button styles flex and bounce when pressed.
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
                .liquidGlass(in: Capsule(), tint: prominent ? Liquid.accent : nil)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(LiquidPressStyle())
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
