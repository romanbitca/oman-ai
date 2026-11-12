import AppKit
import QuartzCore
import SwiftUI

/// How the Floating look sets its words off from what is behind them.
struct FloatingBackdrop: Hashable, Sendable {
    /// How far what is behind is blurred, in points. None at 0.
    var blur: CGFloat = 28
    /// How much everything behind is darkened, alike, from 0 to 1.
    var dim: CGFloat = 0.24
    /// The brightest anything behind may stay, from 0 to 1. At 1 nothing is pressed down. Below it, bright things
    /// are darkened toward it and dark ones are left alone.
    var ceiling: CGFloat = 1
    /// The shadow under the letters.
    var shadowOpacity: Double = 0.3
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
        if look.blur > 0 || look.ceiling < 1,
           let blur = BackdropBlur.makeLayer(points: look.blur, strength: strength, frame: bounds, ceiling: look.ceiling) {
            layer.addSublayer(blur)
        }
        guard look.dim > 0 else { return }
        let shade = CALayer()
        shade.frame = bounds
        shade.backgroundColor = NSColor.black.withAlphaComponent(look.dim).cgColor
        let mask = CALayer()
        mask.frame = bounds
        mask.contents = strength
        shade.mask = mask
        layer.addSublayer(shade)
    }

    /// White, opaque over the middle of the ellipse that fills `size` and clear at its edge, with a smooth fall.
    nonisolated static func feather(size: CGSize, pointsPerPixel: CGFloat = 2) -> CGImage? {
        let width = max(Int((size.width / pointsPerPixel).rounded(.up)), 1)
        let height = max(Int((size.height / pointsPerPixel).rounded(.up)), 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let dx = (CGFloat(column) + 0.5) / CGFloat(width) * 2 - 1
                let dy = (CGFloat(row) + 0.5) / CGFloat(height) * 2 - 1
                let value = strength(atDistance: (dx * dx + dy * dy).squareRoot())
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

    /// 1 out to a third of the way from the middle, then easing down to 0 at the edge, slowly at first and last, so
    /// no line shows where the blur ends. `distance` is 0 at the middle and 1 at the ellipse's edge.
    nonisolated static func strength(atDistance distance: CGFloat) -> CGFloat {
        let fall = min(max((1 - distance) / 0.67, 0), 1)
        // Rounding can lift the curve a hair above 1 just inside full strength.
        return min(fall * fall * fall * (fall * (fall * 6 - 15) + 10), 1)
    }
}
