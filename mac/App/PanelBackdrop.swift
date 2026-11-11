import AppKit
import OmanUI
import QuartzCore

/// The dimmed, slightly blurred side of the screen behind the panel, as behind Control Center.
/// It never takes a click, so a click beside the panel still reaches the app there and closes the panel.
@MainActor
final class PanelBackdrop {
    private enum Look {
        static let dim: CGFloat = 0.22
        /// The blurred desktop is laid over the sharp one at this strength, which keeps the blur slight.
        static let blur: CGFloat = 0.75
        static let fadeIn: TimeInterval = 0.2
        static let fadeOut: TimeInterval = 0.15
    }

    private let window: NSWindow
    private let blurView = NSVisualEffectView()
    private let shadeView = ShadeView()
    private var isShown = false
    private var generation = 0

    init() {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        // Dark, as Control Center's is in light mode too.
        window.appearance = NSAppearance(named: .darkAqua)

        let content = NSView()
        blurView.blendingMode = .behindWindow
        blurView.material = .fullScreenUI
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        shadeView.wantsLayer = true
        shadeView.autoresizingMask = [.width, .height]
        content.addSubview(blurView)
        content.addSubview(shadeView)
        window.contentView = content
    }

    /// Puts the backdrop just below `panel`, which must already be on screen, and fades it in.
    func show(below panel: NSWindow, sideMargin: CGFloat) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let tiles = panel.frame.insetBy(dx: sideMargin, dy: 0)
        let layout = PanelBackdropLayout(screen: screen.frame, menuBarBottom: screen.visibleFrame.maxY, tiles: tiles)
        guard layout.frame.width > 0, layout.frame.height > 0 else { return }

        generation += 1
        window.setFrame(layout.frame, display: false)
        let bounds = NSRect(origin: .zero, size: layout.frame.size)
        blurView.frame = bounds
        shadeView.frame = bounds
        blurView.maskImage = Self.fadeMask(size: layout.frame.size, layout: layout, strength: Look.blur)
        shadeView.shade(layout: layout, strength: Look.dim)
        window.order(.below, relativeTo: panel.windowNumber)

        // A panel already showing its backdrop only moves it, without fading it in again.
        guard !isShown else { return }
        isShown = true
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Look.fadeIn
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        let hiding = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Look.fadeOut
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A show that started during the fade keeps the window on screen.
                guard let self, !self.isShown, self.generation == hiding else { return }
                self.window.orderOut(nil)
            }
        }
    }

    /// Transparent on the band's open side, rising to `strength` across the fade, then even.
    private static func fadeMask(size: NSSize, layout: PanelBackdropLayout, strength: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let full = NSColor.black.withAlphaComponent(strength)
            let gradient = NSGradient(
                colors: [.clear, full, full],
                atLocations: [0, layout.fadeFraction, 1],
                colorSpace: .deviceRGB
            )
            gradient?.draw(in: rect, angle: layout.isAnchoredRight ? 0 : 180)
            return true
        }
    }
}

private final class ShadeView: NSView {
    override func makeBackingLayer() -> CALayer { CAGradientLayer() }

    func shade(layout: PanelBackdropLayout, strength: CGFloat) {
        guard let gradient = layer as? CAGradientLayer else { return }
        let full = NSColor.black.withAlphaComponent(strength).cgColor
        gradient.colors = [NSColor.clear.cgColor, full, full]
        gradient.locations = [0, NSNumber(value: Double(layout.fadeFraction)), 1]
        gradient.startPoint = CGPoint(x: layout.isAnchoredRight ? 0 : 1, y: 0.5)
        gradient.endPoint = CGPoint(x: layout.isAnchoredRight ? 1 : 0, y: 0.5)
    }
}
