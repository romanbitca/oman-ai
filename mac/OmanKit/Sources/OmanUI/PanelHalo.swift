import AppKit
import SwiftUI

/// A soft-edged blur of whatever is behind the panel, so an app's text doesn't show between the tiles.
/// It plays the part of the blurred backdrop behind Control Center, but only around the panel.
struct PanelHalo: NSViewRepresentable {
    /// How far the blur reaches past the tiles before it has faded out.
    static let spread: CGFloat = 22

    let onClick: () -> Void

    final class HaloView: NSVisualEffectView {
        var onClick: (() -> Void)?

        // The halo is part of the panel's window, so a click on it never reaches the app behind. It closes the
        // panel instead, as a click beside Control Center closes it.
        override func mouseDown(with event: NSEvent) {
            onClick?()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    func makeNSView(context: Context) -> HaloView {
        let view = HaloView()
        view.blendingMode = .behindWindow
        // Of the public materials this one keeps the most of the colours behind it.
        view.material = .fullScreenUI
        view.state = .active
        view.maskImage = Self.mask
        // The tiles are dark, but the blur follows the system's light or dark mode, as Control Center's backdrop does.
        view.appearance = NSApp.effectiveAppearance
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: HaloView, context: Context) {
        view.onClick = onClick
    }

    /// Opaque inside the tiles' outline and fading to clear over `spread` beyond it. It is stretched from its
    /// middle pixel, whose corners sit where the tiles' rounded corners have their centres.
    static let mask: NSImage = {
        let side = maskEdge * 2 + 1
        // Black with the fade in its alpha, premultiplied: an image with only an alpha channel is ignored as a mask.
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                pixels[(y * side + x) * 4 + 3] = maskAlpha(x: x, y: y)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        let image = provider.flatMap {
            CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent
            )
        }
        let mask = image.map { NSImage(cgImage: $0, size: NSSize(width: side, height: side)) } ?? NSImage()
        let inset = CGFloat(maskEdge)
        mask.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        mask.resizingMode = .stretch
        return mask
    }()

    /// From the mask's middle pixel to its edge: the tiles' corner radius, then the fade.
    static let maskEdge = Int(PanelMetrics.tileRadius + spread)

    static func maskAlpha(x: Int, y: Int) -> UInt8 {
        let center = CGFloat(maskEdge)
        let dx = max(abs(CGFloat(x) - center) - 0.5, 0)
        let dy = max(abs(CGFloat(y) - center) - 0.5, 0)
        let beyondTiles = (dx * dx + dy * dy).squareRoot() - PanelMetrics.tileRadius
        let fade = min(max(beyondTiles / spread, 0), 1)
        let eased = fade * fade * (3 - 2 * fade)
        return UInt8(((1 - eased) * 255).rounded())
    }
}
