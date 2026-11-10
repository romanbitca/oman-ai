import Foundation

public protocol WritingService: Sendable {
    /// Yields text deltas as they arrive. Finishes by throwing a `WritingError` on failure.
    func stream(_ request: WritingRequest, apiKey: String) -> AsyncThrowingStream<String, Error>
    /// Throws `WritingError.invalidAPIKey` when Anthropic rejects the key.
    func validate(apiKey: String) async throws
}

public protocol StyleStore: Sendable {
    func loadStyles() throws -> [WritingStyle]
    func save(_ style: WritingStyle) throws
    func deleteStyle(id: UUID) throws
    func lastStyleID(forBundleID bundleID: String) throws -> UUID?
    func setLastStyleID(_ id: UUID?, forBundleID bundleID: String) throws
}

public protocol AppSettingsStore: Sendable {
    func selectedModel() throws -> ClaudeModel
    func setSelectedModel(_ model: ClaudeModel) throws
}

public protocol APIKeyStore: Sendable {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

@MainActor
public protocol SystemBridging: AnyObject {
    var isAccessibilityGranted: Bool { get }
    func requestAccessibility()

    var isScreenCaptureGranted: Bool { get }
    func requestScreenCapture()

    var isLaunchAtLoginEnabled: Bool { get }
    func setLaunchAtLogin(_ enabled: Bool) throws

    func captureSelection() async -> SelectionCapture
    func replaceSelection(expected: String, with text: String, in app: SourceApp) async -> InsertOutcome
    func insertAtCursor(_ text: String, in app: SourceApp?) async -> InsertOutcome
    func copyToClipboard(_ text: String)
    func clipboardText() -> String?
    func captureWindow(of app: SourceApp) async throws -> ScreenshotAttachment
}

/// Implemented by the app shell, which owns the status item and the panel window.
@MainActor
public protocol PanelPresenting: AnyObject {
    func hidePanel()
    func showPanel()
    func setPanelPinned(_ pinned: Bool)
    func openSettings()
}

@MainActor
public struct AppServices {
    public let writing: any WritingService
    public let styles: any StyleStore
    public let settings: any AppSettingsStore
    public let apiKeys: any APIKeyStore
    public let system: any SystemBridging

    public init(
        writing: any WritingService,
        styles: any StyleStore,
        settings: any AppSettingsStore,
        apiKeys: any APIKeyStore,
        system: any SystemBridging
    ) {
        self.writing = writing
        self.styles = styles
        self.settings = settings
        self.apiKeys = apiKeys
        self.system = system
    }
}
