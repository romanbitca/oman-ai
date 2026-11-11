import AppKit

/// The numbers behind the panel's backdrop, measured from Control Center on macOS 27 with a checkerboard behind it.
///
/// Around its modules Control Center blurs what is behind by about 3 points and darkens it by 10%, with no tint:
/// white becomes 90% and black stays black. Both fade with the distance from the modules' outline. The blur is
/// at full strength 45 points inside it and gone 40 points outside. The darkening is full 34 points inside and
/// gone 126 points outside. Everything further away is untouched.
public struct PanelBackdropLayout: Equatable, Sendable {
    public struct BlurStep: Equatable, Sendable {
        /// How far this step reaches beyond the tiles. Negative is inside their outline.
        public let outset: CGFloat
        /// The window server's blur radius. Three units blur by about one point.
        public let radius: Int32
    }

    /// From the outside in. The window server's blur is all or nothing inside a window's shape, so the soft edge
    /// is built from nested windows. Each blurs what the ones before it left, and the strengths add up as the
    /// root of the sum of their squares: 0.7, 1.2, 1.6, 2.1, 2.5 and 3 points.
    public static let blurSteps = [
        BlurStep(outset: 31, radius: 2),
        BlurStep(outset: 14, radius: 3),
        BlurStep(outset: 1, radius: 3),
        BlurStep(outset: -11, radius: 4),
        BlurStep(outset: -24, radius: 4),
        BlurStep(outset: -37, radius: 5),
    ]

    /// Each blur window needs a fill the window server can see. Together the fills are part of the darkening.
    static let blurFillAlpha: CGFloat = 3.0 / 255
    static let dimStrength: CGFloat = 0.10
    /// The darkening is full this far inside the tiles' outline...
    static let dimFullInset: CGFloat = 34
    /// ...and gone this far outside it.
    public static let dimReach: CGFloat = 126

    /// The panel's glass, in screen coordinates.
    public let tiles: CGRect
    /// Where the backdrop may draw: the panel's screen below the menu bar.
    public let bounds: CGRect
    public let cornerRadius: CGFloat

    public init(tiles: CGRect, bounds: CGRect) {
        self.init(tiles: tiles, bounds: bounds, cornerRadius: PanelMetrics.tileRadius)
    }

    init(tiles: CGRect, bounds: CGRect, cornerRadius: CGFloat) {
        self.tiles = tiles
        self.bounds = bounds
        self.cornerRadius = cornerRadius
    }

    /// The outline of one blur step, which may reach past `bounds`.
    public func shape(for step: BlurStep) -> (rect: CGRect, cornerRadius: CGFloat) {
        // A step never insets the tiles to nothing, however short the panel is.
        let deepest = max(0, min(tiles.width, tiles.height) / 2 - 1)
        let outset = max(step.outset, -deepest)
        return (tiles.insetBy(dx: -outset, dy: -outset), max(0, cornerRadius + outset))
    }

    public func frame(for step: BlurStep) -> CGRect {
        shape(for: step).rect.intersection(bounds)
    }

    public var dimFrame: CGRect {
        tiles.insetBy(dx: -Self.dimReach, dy: -Self.dimReach).intersection(bounds)
    }

    /// How far a point is outside the tiles' rounded outline. Negative inside.
    public func distance(to point: CGPoint) -> CGFloat {
        let radius = min(cornerRadius, min(tiles.width, tiles.height) / 2)
        let qx = abs(point.x - tiles.midX) - (tiles.width / 2 - radius)
        let qy = abs(point.y - tiles.midY) - (tiles.height / 2 - radius)
        let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
        return outside + min(max(qx, qy), 0) - radius
    }

    /// The darkening Control Center has at that distance from its modules.
    public static func dim(atDistance distance: CGFloat) -> CGFloat {
        let ramp = (dimReach - distance) / (dimReach + dimFullInset)
        return dimStrength * min(max(ramp, 0), 1)
    }

    /// What the dim layer adds at that distance, so that with the blur windows' own faint fills over it the
    /// total is `dim(atDistance:)`.
    public static func dimLayerAlpha(atDistance distance: CGFloat) -> CGFloat {
        var fills = 0
        for step in blurSteps where distance <= step.outset {
            fills += 1
        }
        let seenThroughFills = pow(1 - blurFillAlpha, CGFloat(fills))
        return max(0, 1 - (1 - dim(atDistance: distance)) / seenThroughFills)
    }

    /// The dim layer as black pixels with the darkening in their alpha, one pixel for every `pointsPerPixel` points
    /// of `dimFrame`, top row first.
    func dimPixels(pointsPerPixel: CGFloat) -> (pixels: [UInt8], width: Int, height: Int) {
        let frame = dimFrame
        let width = max(1, Int((frame.width / pointsPerPixel).rounded(.up)))
        let height = max(1, Int((frame.height / pointsPerPixel).rounded(.up)))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let y = frame.maxY - (CGFloat(row) + 0.5) * pointsPerPixel
            for column in 0..<width {
                let x = frame.minX + (CGFloat(column) + 0.5) * pointsPerPixel
                let alpha = Self.dimLayerAlpha(atDistance: distance(to: CGPoint(x: x, y: y)))
                pixels[(row * width + column) * 4 + 3] = UInt8((alpha * 255).rounded())
            }
        }
        return (pixels, width, height)
    }
}

/// The slight blur and darkening behind the panel, as behind Control Center. Its windows never take a click, so a
/// click beside the panel still reaches the app there and closes the panel.
@MainActor
public final class PanelBackdrop {
    /// False when the window server's blur can't be found. The panel then keeps frosted glass and no backdrop.
    public static var isAvailable: Bool { WindowBlur.isAvailable }

    private final class ShapeView: NSView {
        var shape = CGRect.zero
        var cornerRadius: CGFloat = 0

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(PanelBackdropLayout.blurFillAlpha).setFill()
            NSBezierPath(roundedRect: shape, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
    }

    private let dimWindow = PanelBackdrop.makeWindow()
    private let dimView = NSView()
    private var dimLayer: CALayer?
    private let blurWindows: [NSWindow]
    private let blurViews: [ShapeView]
    private var layout: PanelBackdropLayout?
    private var isShown = false

    public init() {
        dimView.wantsLayer = true
        dimWindow.contentView = dimView
        blurWindows = PanelBackdropLayout.blurSteps.map { _ in PanelBackdrop.makeWindow() }
        blurViews = blurWindows.map { window in
            let view = ShapeView()
            window.contentView = view
            return view
        }
        for (window, step) in zip(blurWindows, PanelBackdropLayout.blurSteps) {
            WindowBlur.set(radius: step.radius, for: window)
        }
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        return window
    }

    /// Puts the backdrop around the panel's tiles, just below `panel`, which must already be on screen.
    /// Called again when the tiles change size, it moves there.
    public func show(_ layout: PanelBackdropLayout, below panel: NSWindow) {
        guard Self.isAvailable, layout != self.layout || !isShown else { return }
        // Tiles that are off their screen leave nothing to draw.
        guard !layout.dimFrame.isEmpty, !layout.frame(for: PanelBackdropLayout.blurSteps[0]).isEmpty else {
            hide()
            return
        }
        let previous = isShown ? self.layout : nil
        self.layout = layout

        for (index, step) in PanelBackdropLayout.blurSteps.enumerated() {
            let frame = layout.frame(for: step)
            let shape = layout.shape(for: step)
            guard !frame.isEmpty else {
                blurWindows[index].orderOut(nil)
                continue
            }
            blurWindows[index].setFrame(frame, display: false)
            // The views count from the top left, where the panel hangs, so a taller panel only adds below.
            blurViews[index].shape = CGRect(
                x: shape.rect.minX - frame.minX,
                y: frame.maxY - shape.rect.maxY,
                width: shape.rect.width,
                height: shape.rect.height
            )
            blurViews[index].cornerRadius = shape.cornerRadius
            blurViews[index].needsDisplay = true
        }
        let jump = abs(layout.tiles.height - (previous?.tiles.height ?? 0)) + abs(layout.tiles.minX - (previous?.tiles.minX ?? 0))
        dimWindow.setFrame(layout.dimFrame, display: false)
        // While text streams in the panel grows a line at a time, which is too small a step to cross-fade.
        replaceDimLayer(for: layout, fading: isShown && jump > 40)

        // Lowest first: each lands just under the panel, above the ones before it.
        dimWindow.order(.below, relativeTo: panel.windowNumber)
        for (window, step) in zip(blurWindows, PanelBackdropLayout.blurSteps) where !layout.frame(for: step).isEmpty {
            window.order(.below, relativeTo: panel.windowNumber)
        }

        guard !isShown else { return }
        isShown = true
        dimWindow.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            dimWindow.animator().alphaValue = 1
        }
    }

    public func hide() {
        guard isShown else { return }
        isShown = false
        dimWindow.orderOut(nil)
        blurWindows.forEach { $0.orderOut(nil) }
    }

    private func replaceDimLayer(for layout: PanelBackdropLayout, fading: Bool) {
        // The darkening changes slowly from point to point, so a quarter of the pixels is plenty.
        let pointsPerPixel: CGFloat = 2
        let dim = layout.dimPixels(pointsPerPixel: pointsPerPixel)
        guard let provider = CGDataProvider(data: Data(dim.pixels) as CFData),
              let image = CGImage(
                  width: dim.width, height: dim.height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: dim.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else { return }

        let old = dimLayer
        let new = CALayer()
        new.contents = image
        new.magnificationFilter = .linear
        dimLayer = new

        // Both layers hang from the top of the window, where the panel does.
        let top = layout.dimFrame.height
        let size = CGSize(width: CGFloat(dim.width) * pointsPerPixel, height: CGFloat(dim.height) * pointsPerPixel)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        new.frame = CGRect(x: 0, y: top - size.height, width: size.width, height: size.height)
        if let old {
            old.frame.origin.y = top - old.frame.height
        }
        dimView.layer?.addSublayer(new)
        if fading { new.opacity = 0 }
        CATransaction.commit()

        guard fading else {
            old?.removeFromSuperlayer()
            return
        }
        // A panel that changes height cross-fades to its new darkening instead of jumping.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setCompletionBlock { old?.removeFromSuperlayer() }
        new.opacity = 1
        old?.opacity = 0
        CATransaction.commit()
    }
}
