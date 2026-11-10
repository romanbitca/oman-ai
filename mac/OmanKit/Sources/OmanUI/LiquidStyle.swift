import AppKit
import SwiftUI

enum Liquid {
    static let morph = Animation.spring(response: 0.46, dampingFraction: 0.78)
    static let press = Animation.spring(response: 0.26, dampingFraction: 0.62)
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

struct PanelDragHandle: View {
    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.42))
            .frame(width: 34, height: 4)
            .frame(width: 88, height: 20)
            .background(WindowDragArea())
            .liquidGlass(in: Capsule())
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
    let interactive: Bool
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
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    func liquidGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        id: String? = nil
    ) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint, interactive: interactive, id: id))
    }
}

struct LiquidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Liquid.press, value: configuration.isPressed)
    }
}

struct LiquidButton: View {
    let title: String
    var symbol: String?
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .modifier(LiquidButtonChrome(prominent: prominent))
    }
}

private struct LiquidButtonChrome: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        let sized = content.controlSize(.large).font(.system(size: 13, weight: .medium))
        if #available(macOS 26.0, *) {
            if prominent {
                sized.buttonStyle(.glassProminent).tint(Liquid.accent)
            } else {
                sized.buttonStyle(.glass)
            }
        } else if prominent {
            sized.buttonStyle(.borderedProminent).tint(Liquid.accent)
        } else {
            sized.buttonStyle(.bordered)
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
