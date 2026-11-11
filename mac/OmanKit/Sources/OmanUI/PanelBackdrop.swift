import AppKit

/// The numbers behind the panel's backdrop, measured from Control Center on macOS 27 with a checkerboard behind it.
///
/// Around its modules Control Center blurs what is behind by about 3 points and darkens it by 10%, with no tint:
/// white becomes 90% and black stays black. Both fade with the distance from the modules' outline. The blur
/// grows evenly from nothing 45 points outside it to its full strength 45 points inside: it measures half a
/// point 30 points out and one point 14 points out. The darkening is full 34 points inside and gone 126 points
/// outside. Everything further away is untouched.
public struct PanelBackdropLayout: Equatable, Sendable {
    static let blurPoints: CGFloat = 3
    /// The blur is full this far inside the tiles' outline...
    static let blurFullInset: CGFloat = 45
    /// ...and gone this far outside it.
    public static let blurReach: CGFloat = 45
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

    /// Everything the backdrop touches, which is as far as the darkening reaches.
    public var frame: CGRect {
        tiles.insetBy(dx: -Self.dimReach, dy: -Self.dimReach).intersection(bounds)
    }

    /// The part of `frame` that is blurred at all.
    public var blurFrame: CGRect {
        tiles.insetBy(dx: -Self.blurReach, dy: -Self.blurReach).intersection(bounds)
    }

    /// How far a point is outside the tiles' rounded outline. Negative inside.
    public func distance(to point: CGPoint) -> CGFloat {
        let radius = min(cornerRadius, min(tiles.width, tiles.height) / 2)
        let qx = abs(point.x - tiles.midX) - (tiles.width / 2 - radius)
        let qy = abs(point.y - tiles.midY) - (tiles.height / 2 - radius)
        let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
        return outside + min(max(qx, qy), 0) - radius
    }

    /// How much of the full blur there is at that distance from the tiles, from 0 to 1. It grows a little with
    /// every point, so there is no line where the blur begins.
    public static func blur(atDistance distance: CGFloat) -> CGFloat {
        min(max((blurReach - distance) / (blurReach + blurFullInset), 0), 1)
    }

    /// The darkening Control Center has at that distance from its modules.
    public static func dim(atDistance distance: CGFloat) -> CGFloat {
        let ramp = (dimReach - distance) / (dimReach + dimFullInset)
        return dimStrength * min(max(ramp, 0), 1)
    }

    /// One value from 0 to 255 for every `pointsPerPixel` points of `area`, top row first, from the distance
    /// of each spot to the tiles.
    func map(of area: CGRect, pointsPerPixel: CGFloat, _ value: (CGFloat) -> CGFloat) -> (values: [UInt8], width: Int, height: Int) {
        let width = max(1, Int((area.width / pointsPerPixel).rounded(.up)))
        let height = max(1, Int((area.height / pointsPerPixel).rounded(.up)))
        var values = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let y = area.maxY - (CGFloat(row) + 0.5) * pointsPerPixel
            for column in 0..<width {
                let x = area.minX + (CGFloat(column) + 0.5) * pointsPerPixel
                values[row * width + column] = UInt8((value(distance(to: CGPoint(x: x, y: y))) * 255).rounded())
            }
        }
        return (values, width, height)
    }
}

/// The slight blur and darkening behind the panel, as behind Control Center. Its window never takes a click, so
/// a click beside the panel still reaches the app there and closes the panel.
@MainActor
public final class PanelBackdrop {
    /// False when Core Animation's backdrop blur can't be found, and before macOS 26: the clear look was
    /// measured with that system's glass. The panel then keeps frosted glass and no backdrop.
    public static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            BackdropBlur.isAvailable
        } else {
            false
        }
    }

    /// The blur and the darkening change slowly from point to point, so a quarter of the pixels is plenty.
    private static let pointsPerPixel: CGFloat = 2

    private let window: NSWindow
    private let view = NSView()
    /// The layers that show the present layout: the blur with its fade, and the darkening over it.
    private var layers: CALayer?
    private var layout: PanelBackdropLayout?
    private var isShown = false

    public init() {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        view.wantsLayer = true
        window.contentView = view
    }

    /// Puts the backdrop around the panel's tiles, just below `panel`, which must already be on screen.
    /// Called again when the tiles change size, it moves there.
    public func show(_ layout: PanelBackdropLayout, below panel: NSWindow) {
        guard Self.isAvailable, layout != self.layout || !isShown else { return }
        // Tiles that are off their screen leave nothing to draw.
        guard !layout.frame.isEmpty, !layout.blurFrame.isEmpty else {
            hide()
            return
        }
        let previous = isShown ? self.layout : nil
        self.layout = layout

        let jump = abs(layout.tiles.height - (previous?.tiles.height ?? 0)) + abs(layout.tiles.minX - (previous?.tiles.minX ?? 0))
        window.setFrame(layout.frame, display: false)
        // While text streams in the panel grows a line at a time, which is too small a step to cross-fade.
        replaceLayers(for: layout, fading: isShown && jump > 40)
        window.order(.below, relativeTo: panel.windowNumber)

        guard !isShown else { return }
        isShown = true
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 1
        }
    }

    public func hide() {
        guard isShown else { return }
        isShown = false
        window.orderOut(nil)
    }

    private func replaceLayers(for layout: PanelBackdropLayout, fading: Bool) {
        let frame = layout.frame
        let new = CALayer()
        // The window's layers count from its bottom left.
        func placed(_ area: CGRect) -> CGRect {
            CGRect(x: area.minX - frame.minX, y: area.minY - frame.minY, width: area.width, height: area.height)
        }

        let strength = layout.map(of: layout.blurFrame, pointsPerPixel: Self.pointsPerPixel, PanelBackdropLayout.blur)
        if let image = Self.image(strength, isMask: true),
           let blur = BackdropBlur.makeLayer(points: PanelBackdropLayout.blurPoints, strength: image, frame: placed(layout.blurFrame)) {
            new.addSublayer(blur)
        }
        if let shade = Self.image(layout.map(of: frame, pointsPerPixel: Self.pointsPerPixel, PanelBackdropLayout.dim), isMask: false) {
            let dim = CALayer()
            dim.frame = placed(frame)
            dim.contents = shade
            dim.magnificationFilter = .linear
            new.addSublayer(dim)
        }

        let old = layers
        layers = new
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        new.frame = CGRect(origin: .zero, size: frame.size)
        // The old layers hang from the top of the window, where the panel does, while the window changes height.
        if let old {
            old.frame.origin.y = frame.height - old.frame.height
        }
        view.layer?.addSublayer(new)
        if fading { new.opacity = 0 }
        CATransaction.commit()

        guard fading else {
            old?.removeFromSuperlayer()
            return
        }
        // A panel that changes height cross-fades to its new backdrop instead of jumping.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setCompletionBlock { old?.removeFromSuperlayer() }
        new.opacity = 1
        old?.opacity = 0
        CATransaction.commit()
    }

    /// The map as a picture. A mask is white with the value in its alpha; the darkening is black with it.
    private static func image(_ map: (values: [UInt8], width: Int, height: Int), isMask: Bool) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: map.width * map.height * 4)
        for (index, value) in map.values.enumerated() {
            if isMask {
                pixels[index * 4] = value
                pixels[index * 4 + 1] = value
                pixels[index * 4 + 2] = value
            }
            pixels[index * 4 + 3] = value
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: map.width, height: map.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: map.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
