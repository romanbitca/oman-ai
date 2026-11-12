import AppKit
import QuartzCore
import SwiftUI

/// How the Floating look sets its words off from what is behind them. Only what is bright behind them is darkened,
/// as much as white words need to be read, and what is dark is left alone. An even darkening, as before 0.4.5,
/// showed as a dark cloud over a desktop picture and was still too faint over a white window.
struct FloatingBackdrop: Hashable, Sendable {
    /// How far what is behind is blurred, in points. None at 0.
    var blur: CGFloat = 28
    /// What white behind the words comes out as, from 0 to 1. At 1 nothing is darkened this way.
    var whiteLevel: CGFloat = 0.55
    /// How far out from the middle that darkening keeps its full strength, as a share of the way to the edge.
    var curveReach: CGFloat = 0.45
    /// How much everything behind is darkened alike where bright things can't be darkened on their own: on a macOS
    /// without the filter, or with `whiteLevel` at 1.
    var fallbackDim: CGFloat = 0.24
    /// The shadow under the letters.
    var shadowOpacity: Double = 0.35
    var shadowRadius: CGFloat = 3
}

extension EnvironmentValues {
    @Entry var floatingBackdrop = FloatingBackdrop()
}

/// Blurs and darkens whatever is behind the window, fully in the middle and fading to nothing at the edges of the
/// ellipse that fills the view, so words can float on it with no box around them. It uses the panel backdrop's
/// tint-free blur; where that is missing, only the darkening shows.
struct SoftBlur: NSViewRepresentable {
    var look: FloatingBackdrop

    func makeNSView(context: Context) -> SoftBlurView {
        SoftBlurView(look: look)
    }

    func updateNSView(_ view: SoftBlurView, context: Context) {}
}

final class SoftBlurView: NSView {
    private let look: FloatingBackdrop
    private var builtSize = CGSize.zero

    init(look: FloatingBackdrop) {
        self.look = look
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard bounds.size != builtSize, bounds.width > 1, bounds.height > 1 else { return }
        builtSize = bounds.size
        rebuild()
    }

    private func rebuild() {
        guard let layer else { return }
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let strength = Self.feather(size: bounds.size) else { return }
        var darkensBright = false
        if look.whiteLevel < 1, let fade = Self.feather(size: bounds.size, full: look.curveReach),
           let curve = BackdropBlur.makeCurveLayer(whiteLevel: look.whiteLevel, fade: fade, frame: bounds) {
            // Under the blur, which then blurs what it darkened. As a filter after the blur, it needed a fade of
            // its own on the same layer, and the blur faded twice as fast with it.
            layer.addSublayer(curve)
            darkensBright = true
        }
        if look.blur > 0, let blur = BackdropBlur.makeLayer(points: look.blur, strength: strength, frame: bounds) {
            layer.addSublayer(blur)
        }
        let dim = darkensBright ? 0 : look.fallbackDim
        guard dim > 0 else { return }
        let shade = CALayer()
        shade.frame = bounds
        shade.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
        let mask = CALayer()
        mask.frame = bounds
        mask.contents = strength
        shade.mask = mask
        layer.addSublayer(shade)
    }

    /// White, opaque over the middle of the ellipse that fills `size` and clear at its edge, with a smooth fall.
    nonisolated static func feather(size: CGSize, full: CGFloat = 1.0 / 3, pointsPerPixel: CGFloat = 2) -> CGImage? {
        let width = max(Int((size.width / pointsPerPixel).rounded(.up)), 1)
        let height = max(Int((size.height / pointsPerPixel).rounded(.up)), 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let dx = (CGFloat(column) + 0.5) / CGFloat(width) * 2 - 1
                let dy = (CGFloat(row) + 0.5) / CGFloat(height) * 2 - 1
                let value = strength(atDistance: (dx * dx + dy * dy).squareRoot(), full: full)
                let byte = UInt8((value * 255).rounded())
                let index = (row * width + column) * 4
                pixels[index] = byte
                pixels[index + 1] = byte
                pixels[index + 2] = byte
                pixels[index + 3] = byte
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// 1 out to `full` of the way from the middle, a third unless told otherwise, then easing down to 0 at the edge,
    /// slowly at first and last, so no line shows where the blur ends. `distance` is 0 at the middle and 1 at the
    /// ellipse's edge.
    nonisolated static func strength(atDistance distance: CGFloat, full: CGFloat = 1.0 / 3) -> CGFloat {
        let fall = min(max((1 - distance) / max(1 - full, 0.01), 0), 1)
        // Rounding can lift the curve a hair above 1 just inside full strength.
        return min(fall * fall * fall * (fall * (fall * 6 - 15) + 10), 1)
    }
}
