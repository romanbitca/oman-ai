import AppKit
import OmanUI

/// Holds the glass pill with the live words of a dictation. It never takes the keyboard, so the app being
/// dictated into keeps its cursor and the words can be pasted there.
final class DictationPillWindow: NSPanel {
    init() {
        // .nonactivatingPanel must be set here: adding it after init does not update the window server.
        super.init(
            contentRect: NSRect(origin: .zero, size: DictationPillMetrics.windowSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        // A window shadow would freeze the outline of glass that is still reshaping.
        hasShadow = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Glass in a window that isn't key is drawn darker and flat, and this window is never key. See FloatingPanel.
    @objc var hasKeyAppearance: Bool { true }
}
