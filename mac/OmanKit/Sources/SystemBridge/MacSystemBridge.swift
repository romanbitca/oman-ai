import AppKit
import ApplicationServices
import OmanCore
import ServiceManagement

@MainActor
public final class MacSystemBridge: SystemBridging {
    private static let pollInterval = Duration.milliseconds(10)
    private static let activationTimeout = Duration.milliseconds(400)
    private static let keyWindowSettle = Duration.milliseconds(120)

    private let clipboard = ClipboardRoute(
        pasteboard: .general,
        postCopy: KeyEvents.postCopy,
        postPaste: KeyEvents.postPaste
    )
    private let hotKeys = GlobalHotKeys()
    // CoreFoundation's equality is how two Accessibility references are compared.
    private var insertionTarget = InsertionTarget<AXUIElement> { CFEqual($0, $1) }

    public init() {}

    // MARK: Appearance and shortcuts

    public func setAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    public var onGlobalShortcut: (@MainActor (ShortcutAction) -> Void)? {
        get { hotKeys.onTrigger }
        set { hotKeys.onTrigger = newValue }
    }

    @discardableResult
    public func registerGlobalShortcuts(_ shortcuts: [ShortcutAction: KeyCombo]) -> Set<ShortcutAction> {
        hotKeys.register(shortcuts)
    }

    public func suspendGlobalShortcuts() {
        hotKeys.unregisterAll()
    }

    // MARK: Permissions

    public var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    public func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public var isScreenCaptureGranted: Bool { CGPreflightScreenCaptureAccess() }

    public func requestScreenCapture() {
        CGRequestScreenCaptureAccess()
    }

    public var isLaunchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    // MARK: Selection

    public func captureSelection() async -> SelectionCapture {
        // Whatever was remembered belongs to an earlier panel.
        insertionTarget.remember(nil, processID: 0)
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return SelectionCapture(app: nil, text: nil)
        }
        let app = SourceApp(
            name: front.localizedName ?? "App",
            bundleID: front.bundleIdentifier,
            processID: front.processIdentifier
        )
        guard AXIsProcessTrusted() else {
            return SelectionCapture(app: app, text: nil)
        }
        let focused = SelectionReader.focusedElement(processID: front.processIdentifier)
        insertionTarget.remember(focused, processID: front.processIdentifier)
        let text = await readSelection(focused: focused, bundleID: front.bundleIdentifier)
        return SelectionCapture(app: app, text: SelectionComparison.nonBlank(text))
    }

    public func replaceSelection(expected: String, with text: String, in app: SourceApp) async -> InsertOutcome {
        guard AXIsProcessTrusted() else { return .permissionMissing }
        guard await ensureFrontmost(app) else { return .sourceUnavailable }
        await Waiting.pause(Self.keyWindowSettle)

        let focused = SelectionReader.focusedElement(processID: app.processID)
        guard let current = await readSelection(focused: focused, bundleID: app.bundleID),
              SelectionComparison.matches(current, expected)
        else {
            return .selectionChanged
        }
        await clipboard.paste(text)
        return .inserted
    }

    public func insertAtCursor(_ text: String, in app: SourceApp?) async -> InsertOutcome {
        guard AXIsProcessTrusted() else { return .permissionMissing }
        if let app {
            guard await ensureFrontmost(app) else { return .sourceUnavailable }
        } else {
            guard let front = NSWorkspace.shared.frontmostApplication,
                  front.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else {
                return .sourceUnavailable
            }
        }
        await Waiting.pause(Self.keyWindowSettle)
        if let app {
            let focused = SelectionReader.focusedElement(processID: app.processID)
            guard insertionTarget.confirm(focused, processID: app.processID) else { return .focusMoved }
        }
        await clipboard.paste(text)
        return .inserted
    }

    // MARK: Clipboard

    public func copyToClipboard(_ text: String) {
        clipboard.copy(text)
    }

    public var hasClipboardText: Bool { clipboard.offersText }

    public func clipboardText() -> String? {
        SelectionComparison.nonBlank(clipboard.text())
    }

    // MARK: Screen

    public func captureWindow(of app: SourceApp) async throws -> ScreenshotAttachment {
        try await WindowCapture.captureFrontWindow(ofProcess: app.processID)
    }

    // MARK: Private

    private func readSelection(focused: AXUIElement?, bundleID: String?) async -> String? {
        switch SelectionReader.read(focused) {
        case .selected(let text):
            return text
        case .secure, .noSelection:
            return nil
        case .unavailable:
            // A synthetic ⌘C is not sent to apps where it can do more than copy.
            guard !SensitiveApps.skipsSyntheticCopy(bundleID: bundleID) else { return nil }
            return await clipboard.copySelection()
        }
    }

    private func ensureFrontmost(_ app: SourceApp) async -> Bool {
        if isFrontmost(app) { return true }
        guard let running = NSRunningApplication(processIdentifier: app.processID) else { return false }
        running.activate(options: [])
        return await Waiting.poll(every: Self.pollInterval, for: Self.activationTimeout) { isFrontmost(app) }
    }

    private func isFrontmost(_ app: SourceApp) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processID
    }
}
