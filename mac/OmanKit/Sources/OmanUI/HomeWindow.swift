import AppKit
import SwiftUI

/// OmanAI's own window, opened from the menu bar icon's menu or by opening OmanAI again: a plain macOS window
/// whose toolbar opens Settings. Search is in the page, over the transcripts it searches.
@MainActor
public final class HomeWindowController: NSWindowController, NSToolbarDelegate {
    private let model: HomeViewModel
    static let settingsItem = NSToolbarItem.Identifier("OmanHomeSettings")

    public init(model: HomeViewModel) {
        self.model = model
        let window = NSWindow(contentViewController: NSHostingController(rootView: HomeView(model: model)))
        window.title = "OmanAI"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // The bar above the page is the page's own colour, so the window reads as one sheet.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = HomePalette.pageNSColor
        window.isReleasedWhenClosed = false
        let visible = NSScreen.main?.visibleFrame.height ?? HomeMetrics.windowSize.height
        window.setContentSize(NSSize(width: HomeMetrics.windowSize.width, height: min(HomeMetrics.windowSize.height, visible - 80)))
        window.contentMinSize = HomeMetrics.minWindowSize
        window.center()
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "OmanHome")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // Never made from a nib.
        fatalError("init(coder:) is not used")
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.settingsItem]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    public func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard identifier == Self.settingsItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        item.label = "Settings"
        item.toolTip = "OmanAI Settings"
        item.isBordered = true
        item.target = self
        item.action = #selector(openSettings)
        return item
    }

    @objc func openSettings() {
        model.openSettings()
    }

    /// Brings the window to the front. Nothing in it starts with the keyboard: left to AppKit, the search field
    /// would take it, and show its ring, every time the window opens.
    public func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        restFocus()
    }

    /// Hands the keyboard back to the window itself.
    func restFocus() {
        window?.makeFirstResponder(nil)
    }
}
