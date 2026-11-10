import Foundation
import OmanCore

@MainActor
public final class MacSystemBridge: SystemBridging {
    public init() {}

    public var isAccessibilityGranted: Bool { false }
    public func requestAccessibility() {}
    public var isScreenCaptureGranted: Bool { false }
    public func requestScreenCapture() {}
    public var isLaunchAtLoginEnabled: Bool { false }
    public func setLaunchAtLogin(_ enabled: Bool) throws {}

    public func captureSelection() async -> SelectionCapture { SelectionCapture(app: nil, text: nil) }
    public func replaceSelection(expected: String, with text: String, in app: SourceApp) async -> InsertOutcome {
        .sourceUnavailable
    }
    public func insertAtCursor(_ text: String, in app: SourceApp?) async -> InsertOutcome { .sourceUnavailable }
    public func copyToClipboard(_ text: String) {}
    public func clipboardText() -> String? { nil }
    public func captureWindow(of app: SourceApp) async throws -> ScreenshotAttachment {
        throw CocoaError(.featureUnsupported)
    }
}
