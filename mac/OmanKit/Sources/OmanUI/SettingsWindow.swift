#if os(macOS)
import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, writing, dictation, styles, actions, shortcuts, access, spending

    var id: String { rawValue }

    /// Under the page's icon in the toolbar, and the window's title while the page shows.
    var title: String {
        switch self {
        case .general: "General"
        case .writing: "Writing"
        case .dictation: "Dictation"
        case .styles: "Styles"
        case .actions: "Actions"
        case .shortcuts: "Shortcuts"
        case .access: "Key & Permissions"
        case .spending: "Spending"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .writing: "pencil.line"
        case .dictation: "mic"
        case .styles: "quote.opening"
        case .actions: "sparkles"
        case .shortcuts: "command"
        case .access: "key"
        case .spending: "chart.bar"
        }
    }
}

/// Settings as macOS lays it out for Safari or Mail: a tab for each page in the toolbar, over a window that is
/// as tall as the page it shows.
@MainActor
public enum SettingsWindow {
    public static func make(model: SettingsViewModel) -> NSWindow {
        // Room for the title bar and the toolbar above a page: 88 points on macOS 27, and some to spare.
        let chrome: CGFloat = 120
        let screenHeight = NSScreen.main?.visibleFrame.height ?? .greatestFiniteMagnitude
        let tabs = SettingsTabsController(
            model: model,
            maxPageHeight: max(SettingsMetrics.minPageHeight, min(SettingsMetrics.maxPageHeight, screenHeight - chrome))
        )
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = tabs
        tabs.fitWindowBeforeItShows()
        return window
    }
}

@MainActor
final class SettingsTabsController: NSTabViewController, NSWindowDelegate {
    private let model: SettingsViewModel
    private var pageHeights: [SettingsPage: CGFloat] = [:]

    init(model: SettingsViewModel, maxPageHeight: CGFloat) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        for page in SettingsPage.allCases {
            let sizing = SettingsPageSizing(maxHeight: maxPageHeight) { [weak self] height in
                self?.pageHeightChanged(page, to: height)
            }
            let host = NSHostingController(
                rootView: SettingsPageView(page: page, model: model).environment(\.settingsPageSizing, sizing)
            )
            // The window's size is set here, from what each page reports.
            host.sizingOptions = []
            // The window takes its title from the page that shows.
            host.title = page.title
            let item = NSTabViewItem(viewController: host)
            item.label = page.title
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private var selectedPage: SettingsPage? {
        let pages = SettingsPage.allCases
        return pages.indices.contains(selectedTabViewItemIndex) ? pages[selectedTabViewItemIndex] : nil
    }

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, willSelect: tabViewItem)
        // A shortcut that is being recorded belongs to the page being left.
        model.cancelRecording()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        // A page seen before is as tall as it was. One shown for the first time reports its height as it appears.
        if let page = selectedPage, let height = pageHeights[page] {
            fitWindow(toPageHeight: height, animated: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
    }

    /// Gives the window the height of its first page while it is still hidden, so that it opens at its size.
    func fitWindowBeforeItShows() {
        view.window?.layoutIfNeeded()
        guard let page = selectedPage else { return }
        fitWindow(toPageHeight: pageHeights[page] ?? SettingsMetrics.minPageHeight, animated: false)
    }

    private func pageHeightChanged(_ page: SettingsPage, to height: CGFloat) {
        pageHeights[page] = height
        guard page == selectedPage else { return }
        fitWindow(toPageHeight: height, animated: view.window?.isVisible == true)
    }

    /// A window low on the display that grows from its top edge would reach below the display, with the end of
    /// its page out of reach. It moves up by as much as that, but never with its title bar above the display.
    nonisolated static func keepingBottomOnDisplay(_ frame: NSRect, visible: NSRect) -> NSRect {
        guard frame.minY < visible.minY else { return frame }
        var frame = frame
        frame.origin.y = min(visible.minY, visible.maxY - frame.height)
        return frame
    }

    /// Changes the window's height from its top edge, which stays where it is.
    private func fitWindow(toPageHeight height: CGFloat, animated: Bool) {
        guard let window = view.window else { return }
        let content = NSRect(x: 0, y: 0, width: SettingsMetrics.width, height: height)
        var frame = window.frameRect(forContentRect: content)
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        if let visible = window.screen?.visibleFrame {
            frame = Self.keepingBottomOnDisplay(frame, visible: visible)
        }
        guard frame != window.frame else { return }
        guard animated else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SettingsMetrics.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }
}

private struct SettingsPageView: View {
    let page: SettingsPage
    let model: SettingsViewModel

    var body: some View {
        switch page {
        case .general: GeneralSettingsView(model: model)
        case .writing: WritingSettingsView(model: model)
        case .dictation: DictationSettingsView(model: model)
        case .styles: StylesSettingsView(model: model)
        case .actions: ActionsSettingsView(model: model)
        case .shortcuts: ShortcutsSettingsView(model: model)
        case .access: AccessSettingsView(model: model)
        case .spending: SpendingSettingsView(model: model)
        }
    }
}
#endif
