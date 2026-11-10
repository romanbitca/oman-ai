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
    private var panelSizeObservation: NSKeyValueObservation?
    private var isPinned = false

    init(services: AppServices) {
        self.services = services
        super.init()

        let model = PanelViewModel(services: services, presenter: self)
        panelModel = model
        let controller = NSHostingController(rootView: PanelRootView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        panel.contentViewController = controller
        panelSizeObservation = controller.observe(\.preferredContentSize, options: [.new]) { [weak self] _, change in
            guard let size = change.newValue else { return }
            Task { @MainActor in self?.resizePanel(to: size) }
        }
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
        guard let buttonRect = statusButtonScreenRect(),
              let visible = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame
        else { return }

        let width = panel.frame.width
        let margin: CGFloat = 8
        let x = min(max(buttonRect.midX - width / 2, visible.minX + margin), visible.maxX - width - margin)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: buttonRect.minY - 6))
    }

    private func statusButtonScreenRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func resizePanel(to size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
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
