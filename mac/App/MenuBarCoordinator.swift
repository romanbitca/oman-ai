import AppKit
import OmanCore
import OmanUI
import SwiftUI

@MainActor
final class MenuBarCoordinator: NSObject, PanelPresenting {
    private let services: AppServices
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = FloatingPanel()
    private var panelModel: PanelViewModel?
    private var settingsModel: SettingsViewModel?
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private var isPinned = false

    init(services: AppServices) {
        self.services = services
        super.init()

        let model = PanelViewModel(services: services, presenter: self)
        panelModel = model
        let hostingView = NSHostingView(rootView: PanelRootView(model: model))
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView
        panel.onEscape = { [weak self] in self?.dismissPanel() }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "wand.and.sparkles", accessibilityDescription: "oman")
            button.image?.isTemplate = true
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
        if panel.isVisible {
            dismissPanel()
            return
        }
        // The selection must be read before the panel takes keyboard focus.
        Task { @MainActor in
            let capture = await services.system.captureSelection()
            panelModel?.begin(with: capture)
            showPanel()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit oman", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    private func dismissPanel() {
        hidePanel()
        isPinned = false
        panelModel?.panelDidClose()
    }

    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame else { return }

        let width = panel.frame.width
        let margin: CGFloat = 8
        let x = min(max(buttonRect.midX - width / 2, visible.minX + margin), visible.maxX - width - margin)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: buttonRect.minY - 6))
    }

    private func startWatchingOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPinned else { return }
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
        panel.orderOut(nil)
    }

    func showPanel() {
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        startWatchingOutsideClicks()
    }

    func setPanelPinned(_ pinned: Bool) {
        isPinned = pinned
    }

    func openSettings() {
        dismissPanel()
        if settingsWindow == nil {
            let model = SettingsViewModel(services: services)
            settingsModel = model
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsRootView(model: model)))
            window.title = "oman Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsModel?.reload()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
