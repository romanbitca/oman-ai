import AppKit
import OmanCore
import OmanUI
import SwiftUI

@MainActor
final class MenuBarCoordinator: NSObject, PanelPresenting, DictationPresenting {
    private let services: AppServices
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = FloatingPanel()
    private let backdrop = PanelBackdrop()
    private let pillWindow = DictationPillWindow()
    private let pillState = DictationPillState()
    private var dictation: DictationController?
    private var modifierDictation: ModifierKeyDictation?
    private var hidePillTask: Task<Void, Never>?
    private var iconTask: Task<Void, Never>?
    private var panelModel: PanelViewModel?
    private var settingsModel: SettingsViewModel?
    private var settingsWindow: NSWindow?
    private var homeModel: HomeViewModel?
    private var homeWindow: HomeWindowController?
    private var outsideClickMonitor: Any?
    private var isPinned = false
    private var placedOrigin: NSPoint?
    private var contentHeight: CGFloat = 0

    init(services: AppServices) {
        self.services = services
        super.init()

        let model = PanelViewModel(services: services, presenter: self)
        panelModel = model
        let hostingView = PanelHostingView(
            rootView: PanelRootView(model: model, hasBackdrop: PanelBackdrop.isAvailable)
        )
        hostingView.sizingOptions = []
        panel.setContentSize(PanelRootView.windowSize)
        panel.contentView = hostingView
        panel.onEscape = { [weak self] in self?.dismissPanel() }
        panel.onKeyCombo = { [weak self] combo in self?.panelModel?.handlePanelShortcut(combo) ?? false }

        let dictation = DictationController(services: services, presenter: self)
        dictation.panel = model
        model.dictation = dictation
        self.dictation = dictation
        let pillView = PanelHostingView(rootView: DictationPillView(controller: dictation, state: pillState))
        pillView.sizingOptions = []
        pillWindow.setContentSize(DictationPillMetrics.windowSize)
        pillWindow.contentView = pillView

        modifierDictation = ModifierKeyDictation(controller: dictation) { [services] in
            (try? services.settings.preferences()) ?? AppPreferences()
        }
        services.system.onModifierKey = { [weak self] event in
            self?.modifierDictation?.handle(event) { [weak self] in self?.panelDictationField() }
        }

        services.system.onGlobalShortcut = { [weak self] action in self?.handleGlobalShortcut(action) }
        services.system.onGlobalShortcutReleased = { [weak self] action in
            if action == .dictateHold { self?.dictation?.holdReleased() }
        }
        // A while after launch, so starting the app stays quick, the chosen model is loaded for the first dictation.
        Task { @MainActor [services] in
            try? await Task.sleep(for: .seconds(3))
            DictationController.prepareChosenModel(services: services)
        }
        if let preferences = try? services.settings.preferences() {
            services.system.setAppearance(preferences.appearance)
            services.system.registerGlobalShortcuts(preferences.globalShortcuts)
            services.system.watchModifierKeys(preferences.dictationChords)
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
        // While a dictation runs, the moving icon is its stop button.
        if let dictation, dictation.isActive {
            dictation.finishNow()
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
        switch action {
        case .openPanel:
            togglePanel()
        case .dictateHold:
            dictation?.holdPressed(into: panelDictationField())
        case .dictateLong:
            dictation?.longPressed(into: panelDictationField())
        case .cancelDictation:
            dictation?.cancel()
        default:
            openPanel(then: action)
        }
    }

    /// With the panel open and holding the keyboard, a dictation goes into its field instead of the app behind.
    private func panelDictationField() -> PanelField? {
        guard panel.isVisible, panel.isKeyWindow else { return nil }
        return panelModel?.dictationField
    }

    private func openPanel(then action: ShortcutAction?) {
        let keepPinned = isPinned && panel.isVisible
        // Option or Command on their own start working once Accessibility is allowed, without a restart.
        if let preferences = try? services.settings.preferences() {
            services.system.watchModifierKeys(preferences.dictationChords)
        }
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
        menu.addItem(withTitle: "Open OmanAI", action: #selector(openHomeFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "OmanAI Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit OmanAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func openHomeFromMenu() {
        openHome()
    }

    /// OmanAI's own window: what it did, how the person's writing goes, and their transcripts.
    func openHome() {
        dismissPanel()
        let model = homeModel ?? HomeViewModel(services: services)
        model.openSettings = { [weak self] in self?.openSettings() }
        homeModel = model
        model.reload()
        if homeWindow == nil {
            homeWindow = HomeWindowController(model: model)
        }
        NSApp.activate()
        homeWindow?.window?.makeKeyAndOrderFront(nil)
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
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: menuBarBottom(belowTopOf: visible)))
    }

    /// The lower edge of the menu bar. The panel used to hang from the icon's own box, which ends 6 points above
    /// that edge, so its first tile began under the bar. With a menu bar that hides itself the area for apps
    /// reaches the top of the screen, and the bar's window is what says where the bar ends.
    private func menuBarBottom(belowTopOf visible: NSRect) -> CGFloat {
        min(visible.maxY, statusItem.button?.window?.frame.minY ?? visible.maxY)
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
        updateBackdrop()
    }

    func setPanelPinned(_ pinned: Bool) {
        let isNewlyPinned = pinned && !isPinned
        isPinned = pinned
        if isNewlyPinned, panel.isVisible {
            keepGripOnScreen()
        }
        updateBackdrop()
    }

    func setPanelContentHeight(_ height: CGFloat) {
        contentHeight = height
        updateBackdrop()
    }

    /// The slight blur and darkening follow the tiles while the panel hangs from the menu bar. Pinned, it is a
    /// window to work beside, so nothing behind it is touched.
    private func updateBackdrop() {
        let shows = PanelRootView.showsBackdrop(
            isAvailable: PanelBackdrop.isAvailable,
            isPinned: isPinned,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
        guard shows, panel.isVisible, contentHeight > 0, let screen = panel.screen ?? NSScreen.main else {
            backdrop.hide()
            return
        }
        let tiles = PanelRootView.tilesFrame(inWindow: panel.frame, contentHeight: contentHeight)
        var bounds = screen.frame
        bounds.size.height = menuBarBottom(belowTopOf: screen.visibleFrame) - bounds.minY
        backdrop.show(PanelBackdropLayout(tiles: tiles, bounds: bounds), below: panel)
    }

    /// Like Control Center, the panel is dark glass with white text, unless a theme was chosen in Settings.
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
        let model = settingsModel ?? SettingsViewModel(services: services)
        settingsModel = model
        // Before the window is made, so that it opens at the height of what its first page holds.
        model.reload()
        if settingsWindow == nil {
            let window = SettingsWindow.make(model: model)
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: DictationPresenting

    func showDictationPill(at position: DictationPillPosition) {
        hidePillTask?.cancel()
        pillState.position = position
        placePill(at: position)
        let theme = (try? services.settings.preferences().appearance) ?? .system
        pillWindow.appearance = theme == .light ? nil : NSAppearance(named: .darkAqua)
        pillWindow.orderFrontRegardless()
        pillState.isShown = true
    }

    func showPanel(withDictatedText text: String, from app: SourceApp?) {
        panelModel?.begin(withDictatedText: text, from: app)
        showPanel()
    }

    func hideDictationPill() {
        pillState.isShown = false
        hidePillTask?.cancel()
        hidePillTask = Task { [weak self] in
            // Long enough for the pill to fade before its window goes.
            try? await Task.sleep(for: .milliseconds(220))
            guard let self, !Task.isCancelled, !self.pillState.isShown else { return }
            self.pillWindow.orderOut(nil)
        }
    }

    func setDictationActive(_ active: Bool) {
        iconTask?.cancel()
        iconTask = nil
        guard active else {
            statusItem.button?.image = NSImage(named: "MenuBarIcon")
            statusItem.button?.image?.isTemplate = true
            statusItem.button?.image?.accessibilityDescription = "OmanAI"
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        iconTask = Task { [weak self] in
            var shown: CGFloat = 1
            while !Task.isCancelled {
                guard let self, let dictation = self.dictation else { return }
                let target = dictation.phase == .listening && !reduceMotion
                    ? DictationWave.amplitude(forLevel: dictation.level) : 0.35
                // Eased toward the voice, so the wave moves smoothly instead of jumping with each reading.
                shown += (target - shown) * 0.45
                let image = Self.waveIcon(amplitude: shown)
                image.accessibilityDescription = "OmanAI, dictating"
                self.statusItem.button?.image = image
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func placePill(at position: DictationPillPosition) {
        let size = DictationPillMetrics.windowSize
        switch position {
        case .menuBar:
            guard let buttonRect = statusButtonScreenRect(),
                  let visible = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame
            else { return }
            // The window's side margins are transparent, so they may hang off the screen, as the panel's do.
            let inset: CGFloat = 8 - DictationPillMetrics.sideMargin
            let x = min(max(buttonRect.midX - size.width / 2, visible.minX + inset), visible.maxX - size.width - inset)
            pillWindow.setFrameTopLeftPoint(NSPoint(x: x, y: menuBarBottom(belowTopOf: visible)))
        case .bottom:
            // The screen of the window being typed in.
            guard let visible = (NSScreen.main ?? statusItem.button?.window?.screen)?.visibleFrame else { return }
            pillWindow.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + DictationPillMetrics.bottomGap
            ))
        }
    }

    /// The menu bar icon's wave, drawn with the given height. At 1 it matches MenuBarIcon.svg.
    private static func waveIcon(amplitude: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let path = NSBezierPath(cgPath: DictationWave.cgPath(in: rect, amplitude: amplitude))
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
