import AppKit
import OmanCore
import OmanUI
import SwiftUI

@MainActor
final class MenuBarCoordinator: NSObject, PanelPresenting {
    private let services: AppServices
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = FloatingPanel()
    private let backdrop = PanelBackdrop()
    private var panelModel: PanelViewModel?
    private var settingsModel: SettingsViewModel?
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private var isPinned = false
    private var placedOrigin: NSPoint?

    init(services: AppServices) {
        self.services = services
        super.init()

        let model = PanelViewModel(services: services, presenter: self)
        panelModel = model
        let hostingView = PanelHostingView(rootView: PanelRootView(model: model))
        hostingView.sizingOptions = []
        panel.setContentSize(PanelRootView.windowSize)
        panel.contentView = hostingView
        panel.onEscape = { [weak self] in self?.dismissPanel() }
        panel.onKeyCombo = { [weak self] combo in self?.panelModel?.handlePanelShortcut(combo) ?? false }

        services.system.onGlobalShortcut = { [weak self] action in self?.handleGlobalShortcut(action) }
        if let preferences = try? services.settings.preferences() {
            services.system.setAppearance(preferences.appearance)
            services.system.registerGlobalShortcuts(preferences.globalShortcuts)
        }

        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
            button.image?.accessibilityDescription = "OmanAI"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        togglePanel()
    }

    private func togglePanel() {
        // A pinned panel is a floating window: the icon loads the current selection into it instead of closing it.
        if panel.isVisible, !isPinned {
            dismissPanel()
            return
        }
        openPanel(then: nil)
    }

    private func handleGlobalShortcut(_ action: ShortcutAction) {
        if action == .openPanel {
            togglePanel()
        } else {
            openPanel(then: action)
        }
    }

    private func openPanel(then action: ShortcutAction?) {
        let keepPinned = isPinned && panel.isVisible
        // The selection must be read before the panel takes keyboard focus.
        Task { @MainActor in
            let capture = await services.system.captureSelection()
            panelModel?.begin(with: capture, keepPinned: keepPinned)
            showPanel()
            if let action {
                panelModel?.run(action)
            }
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        if services.updates != nil {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OmanAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func checkForUpdatesFromMenu() {
        services.updates?.checkForUpdates()
    }

    private func dismissPanel() {
        hidePanel()
        isPinned = false
        panelModel?.panelDidClose()
    }

    private func positionPanel() {
        guard let buttonRect = statusButtonScreenRect(),
              let visible = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame
        else { return }

        let width = panel.frame.width
        // The window's side margins are transparent and may hang off the screen, unless the grip is showing in one.
        let inset: CGFloat = isPinned ? 0 : 8 - PanelRootView.windowSideMargin
        let x = min(max(buttonRect.midX - width / 2, visible.minX + inset), visible.maxX - width - inset)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: buttonRect.minY - 5))
    }

    private func statusButtonScreenRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func startWatchingOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPinned else { return }
                // The system hosts the icon's window, so its own clicks arrive here too. Closing now would make the icon's action reopen the panel.
                if self.statusButtonScreenRect()?.contains(NSEvent.mouseLocation) == true { return }
                self.dismissPanel()
            }
        }
    }

    private func stopWatchingOutsideClicks() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: PanelPresenting

    func hidePanel() {
        stopWatchingOutsideClicks()
        backdrop.hide()
        panel.orderOut(nil)
    }

    func showPanel() {
        let wasDragged = placedOrigin.map { $0 != panel.frame.origin } ?? false
        if !(isPinned && wasDragged) {
            positionPanel()
            placedOrigin = panel.frame.origin
        }
        applyPanelAppearance()
        panel.orderFrontRegardless()
        panel.makeKey()
        startWatchingOutsideClicks()
        if !isPinned {
            showBackdrop()
        }
    }

    func setPanelPinned(_ pinned: Bool) {
        let isNewlyPinned = pinned && !isPinned
        isPinned = pinned
        if isNewlyPinned, panel.isVisible {
            keepGripOnScreen()
        }
        // A pinned panel is a window to work beside, so the dimmed backdrop goes away while it is pinned.
        if pinned {
            backdrop.hide()
        } else if panel.isVisible {
            showBackdrop()
        }
    }

    private func showBackdrop() {
        backdrop.show(below: panel, sideMargin: PanelRootView.windowSideMargin)
    }

    /// As in Control Center, the panel is dark glass with white text, unless a theme was chosen in Settings.
    private func applyPanelAppearance() {
        let theme = (try? services.settings.preferences().appearance) ?? .system
        panel.appearance = theme == .system ? NSAppearance(named: .darkAqua) : nil
    }

    private func keepGripOnScreen() {
        guard let visible = panel.screen?.visibleFrame, panel.frame.maxX > visible.maxX else { return }
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width, y: panel.frame.minY))
        placedOrigin = panel.frame.origin
    }

    func openSettings() {
        dismissPanel()
        if settingsWindow == nil {
            let model = SettingsViewModel(services: services)
            settingsModel = model
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: SettingsRootView.windowSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "OmanAI Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.contentView = NSHostingView(rootView: SettingsRootView(model: model))
            window.center()
            settingsWindow = window
        }
        settingsModel?.reload()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
