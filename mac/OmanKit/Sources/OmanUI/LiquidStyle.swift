import AppKit
import SwiftUI

enum Liquid {
    /// Tiles move and resize into their counterparts on the next screen with this.
    static let morph = Animation.smooth(duration: 0.26)
    /// What is on the tiles changes faster than the tiles move, so two screens are never readable on top of
    /// each other.
    static var swap: AnyTransition {
        .opacity.animation(.easeOut(duration: 0.12))
    }

    static let press = Animation.easeOut(duration: 0.12)
    static let accent = Color(red: 0.40, green: 0.34, blue: 1.0)
    /// Laid over clear glass with a luminosity blend, so it sets how bright a tile is and leaves the colour of
    /// what shows through alone. Measured against Control Center's tiles, as is the boost below.
    static let clearGlassShade = Color(white: 0.13, opacity: 0.30)
    /// Control Center shows what is behind a tile more vivid than it is.
    static let clearGlassSaturation = 1.25

    /// The tiles share one glass container, which draws the glass for all of them, so a boost on one tile never
    /// reaches its glass. It goes on the whole panel instead.
    static func colorBoost(usesClearGlass: Bool) -> Double {
        usesClearGlass ? clearGlassSaturation : 1
    }

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
    /// Clear glass, as in Control Center. The panel uses it over its backdrop.
    @Entry var liquidClearGlass = false
    /// Controls inside a glass tile are flat, because Apple's glass isn't meant to sit on glass.
    @Entry var isInsideGlassTile = false
    /// How much the panel boosts colour for its glass.
    @Entry var liquidColorBoost = 1.0
}

private struct OwnColors: ViewModifier {
    @Environment(\.liquidColorBoost) private var boost

    func body(content: Content) -> some View {
        content.saturation(1 / boost)
    }
}

extension View {
    /// For a picture on the panel, such as an app's icon: undoes the panel's colour boost, which is meant for
    /// what shows through the glass.
    func keepingOwnColors() -> some View {
        modifier(OwnColors())
    }
}

/// Which glass a shape gets. Kept apart from the view so the rules can be tested.
struct LiquidGlassChoice: Equatable {
    let isClear: Bool
    let isInteractive: Bool

    init(prefersClear: Bool, isTinted: Bool, isForReading: Bool = false, wantsInteraction: Bool) {
        // A tint is a solid colour, which clear glass would wash out. Text someone reads or types stays on frosted
        // glass: clear glass shows the app behind only slightly blurred, which is fine behind a button's label
        // but not behind a paragraph.
        isClear = prefersClear && !isTinted && !isForReading
        isInteractive = wantsInteraction
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

private struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let id: String?
    let interactive: Bool
    let reading: Bool
    @Environment(\.liquidSpace) private var space
    @Environment(\.liquidClearGlass) private var prefersClear

    private var choice: LiquidGlassChoice {
        LiquidGlassChoice(
            prefersClear: prefersClear,
            isTinted: tint != nil,
            isForReading: reading,
            wantsInteraction: interactive
        )
    }

    func body(content: Content) -> some View {
        matched(surface(content))
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    // Clear glass alone leaves white almost white, and white text can't be read on it. Control
                    // Center darkens its tiles: measured through one, white is 73% and black 13%. A gray layer
                    // over the glass gives that but washes out the colours behind it, so this one changes
                    // brightness only.
                    if choice.isClear { shape.fill(Liquid.clearGlassShade).blendMode(.luminosity) }
                }
                .glassEffect(glass, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { if let tint { shape.fill(tint.opacity(0.4)).allowsHitTesting(false) } }
                .overlay { shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5).allowsHitTesting(false) }
        }
    }

    /// A tile with an identity moves and resizes into the tile with the same identity on the next screen.
    /// Apple's own way to do this, a glass container with glass identities, cost the panel two thirds of
    /// its frames during a screen change: measured, 34 frames a second with it and 119 without.
    @ViewBuilder
    private func matched(_ view: some View) -> some View {
        if let id, let space {
            view.matchedGeometryEffect(id: id, in: space)
        } else {
            view
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        let base = choice.isClear ? Glass.clear : Glass.regular
        let glass = tint.map { base.tint($0) } ?? base
        return choice.isInteractive ? glass.interactive() : glass
    }
}

extension View {
    /// `interactive` is for buttons: in the panel they get Apple's glass, which lights up under the pointer
    /// and flexes when pressed.
    ///
    /// `reading` is for a surface that holds text to read or type. It keeps frosted glass in the panel too.
    func liquidGlass<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        id: String? = nil,
        interactive: Bool = false,
        reading: Bool = false
    ) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint, id: id, interactive: interactive, reading: reading))
    }
}

struct LiquidPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Liquid.press, value: configuration.isPressed)
    }
}

/// For buttons drawn on interactive glass, which shows the press itself, so the label stays as it is.
struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// A glass capsule button, on Apple's interactive glass.
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
                // Only the label dims, as on macOS: faded glass looked gray over a dark background.
                .opacity(isEnabled ? 1 : 0.55)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .contentShape(Capsule())
                .liquidGlass(in: Capsule(), tint: prominent ? Liquid.accent : nil, interactive: true)
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
    /// Room for the soft edge outside the tile.
    private var spread: CGFloat { 30 }

    var body: some View {
        // The colours turn in a Core Animation layer, which the system animates outside the app, and show through
        // an edge that stays still. Drawn again by SwiftUI for every frame, they kept a whole processor core
        // busy for as long as Claude was writing.
        SpinningColors(isSpinning: !reduceMotion)
            .mask {
                ZStack {
                    shape.strokeBorder(lineWidth: 7).blur(radius: 9).opacity(0.75)
                    shape.strokeBorder(lineWidth: 1.5)
                }
                .padding(spread)
            }
            // Larger than the tile on every side, so the soft edge isn't cut off at the tile's outline.
            .padding(-spread)
            .allowsHitTesting(false)
    }
}

private struct SpinningColors: NSViewRepresentable {
    let isSpinning: Bool

    func makeNSView(context: Context) -> SpinningColorsView {
        SpinningColorsView()
    }

    func updateNSView(_ view: SpinningColorsView, context: Context) {
        view.isSpinning = isSpinning
    }
}

private final class SpinningColorsView: NSView {
    private static let spinKey = "spin"
    private let gradient = CAGradientLayer()

    var isSpinning = true {
        didSet {
            if isSpinning != oldValue { updateSpin() }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        // A layer's gradient runs the other way round from SwiftUI's, so the colours go in reversed.
        gradient.colors = Liquid.iridescence.reversed().map { NSColor($0).cgColor }
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        // A square that still covers the view at any angle.
        let side = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Core Animation drops a layer's animations when its view leaves a window.
        updateSpin()
    }

    private func updateSpin() {
        gradient.removeAnimation(forKey: Self.spinKey)
        guard isSpinning, window != nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        // Clockwise on screen, as before.
        spin.toValue = -2 * Double.pi
        spin.duration = 3.2
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        gradient.add(spin, forKey: Self.spinKey)
    }
}
