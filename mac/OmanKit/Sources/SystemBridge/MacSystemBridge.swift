import AppKit
import ApplicationServices
import OmanCore
import ServiceManagement

@MainActor
public final class MacSystemBridge: SystemBridging {
    private static let pollIntervalMilliseconds = 10
    private static let copyTimeoutMilliseconds = 250
    private static let activationTimeoutMilliseconds = 400
    private static let keyWindowSettleMilliseconds = 120
    // Slow Electron apps read the pasteboard well after the key event arrives.
    private static let pasteReadMilliseconds = 500

    private let pasteboard = NSPasteboard.general

    public init() {}

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
        let text = await readSelection(inProcess: front.processIdentifier)
        return SelectionCapture(app: app, text: SelectionComparison.nonBlank(text))
    }

    public func replaceSelection(expected: String, with text: String, in app: SourceApp) async -> InsertOutcome {
        guard AXIsProcessTrusted() else { return .permissionMissing }
        guard await ensureFrontmost(app) else { return .sourceUnavailable }
        await pause(milliseconds: Self.keyWindowSettleMilliseconds)

        guard let current = await readSelection(inProcess: app.processID),
              SelectionComparison.matches(current, expected)
        else {
            return .selectionChanged
        }
        await paste(text)
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
        await pause(milliseconds: Self.keyWindowSettleMilliseconds)
        await paste(text)
        return .inserted
    }

    // MARK: Clipboard

    public func copyToClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func clipboardText() -> String? {
        SelectionComparison.nonBlank(pasteboard.string(forType: .string))
    }

    // MARK: Screen

    public func captureWindow(of app: SourceApp) async throws -> ScreenshotAttachment {
        try await WindowCapture.captureFrontWindow(ofProcess: app.processID)
    }

    // MARK: Private

    private func readSelection(inProcess processID: pid_t) async -> String? {
        switch SelectionReader.read(processID: processID) {
        case .selected(let text):
            return text
        case .secure, .noSelection:
            return nil
        case .unavailable:
            return await copySelectionThroughClipboard()
        }
    }

    private func copySelectionThroughClipboard() async -> String? {
        let snapshot = PasteboardSnapshot(of: pasteboard)
        let originalCount = pasteboard.changeCount
        KeyEvents.postCopy()

        var copied: String?
        // An app can clear the pasteboard before it finishes writing, so wait for the text itself.
        _ = await poll(timeoutMilliseconds: Self.copyTimeoutMilliseconds) {
            guard pasteboard.changeCount != originalCount else { return false }
            copied = pasteboard.string(forType: .string)
            return copied != nil
        }

        if pasteboard.changeCount != originalCount {
            snapshot.restore(to: pasteboard)
        }
        return copied
    }

    private func paste(_ text: String) async {
        let snapshot = PasteboardSnapshot(of: pasteboard)
        pasteboard.writeTransientString(text)
        let writtenCount = pasteboard.changeCount
        KeyEvents.postPaste()
        await pause(milliseconds: Self.pasteReadMilliseconds)
        snapshot.restore(to: pasteboard, ifChangeCountIs: writtenCount)
    }

    private func ensureFrontmost(_ app: SourceApp) async -> Bool {
        if isFrontmost(app) { return true }
        guard let running = NSRunningApplication(processIdentifier: app.processID) else { return false }
        running.activate(options: [])
        return await poll(timeoutMilliseconds: Self.activationTimeoutMilliseconds) { isFrontmost(app) }
    }

    private func isFrontmost(_ app: SourceApp) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processID
    }

    private func poll(timeoutMilliseconds: Int, until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(timeoutMilliseconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            await pause(milliseconds: Self.pollIntervalMilliseconds)
        }
        return condition()
    }

    /// Detached so that cancelling the caller cannot cut a wait short and restore the clipboard too early.
    private func pause(milliseconds: Int) async {
        await Task.detached {
            try? await Task.sleep(for: .milliseconds(milliseconds))
        }.value
    }
}
