import Foundation

public protocol WritingService: Sendable {
    /// Yields text deltas as they arrive. Finishes by throwing a `WritingError` on failure.
    func stream(_ request: WritingRequest, apiKey: String) -> AsyncThrowingStream<String, Error>
    /// Throws `WritingError.invalidAPIKey` when Anthropic rejects the key.
    func validate(apiKey: String) async throws
    /// A sentence to show the user when this model can't run right now, or nil when it can.
    func unavailableReason(for model: WritingModel) -> String?
}

public protocol StyleStore: Sendable {
    func loadStyles() throws -> [WritingStyle]
    func save(_ style: WritingStyle) throws
    func deleteStyle(id: UUID) throws
    func lastStyleID(forBundleID bundleID: String) throws -> UUID?
    func setLastStyleID(_ id: UUID?, forBundleID bundleID: String) throws
}

public protocol AppSettingsStore: Sendable {
    func selectedModel() throws -> WritingModel
    func setSelectedModel(_ model: WritingModel) throws
    func preferences() throws -> AppPreferences
    func setPreferences(_ preferences: AppPreferences) throws
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

    func setAppearance(_ mode: AppearanceMode)

    var onGlobalShortcut: (@MainActor (ShortcutAction) -> Void)? { get set }
    /// Replaces every registered shortcut. Returns the actions whose combination could not be registered.
    @discardableResult
    func registerGlobalShortcuts(_ shortcuts: [ShortcutAction: KeyCombo]) -> Set<ShortcutAction>
    /// Stops shortcuts firing while the user records a new one. Registering again resumes them.
    func suspendGlobalShortcuts()
}

/// Implemented by the app shell, which owns the status item and the panel window.
@MainActor
public protocol PanelPresenting: AnyObject {
    func hidePanel()
    func showPanel()
    func setPanelPinned(_ pinned: Bool)
    func openSettings()
}

/// Implemented by the app shell. Builds without an update signing key don't have one.
@MainActor
public protocol AppUpdating: AnyObject {
    var installsUpdatesAutomatically: Bool { get set }
    func checkForUpdates()
}

@MainActor
public struct AppServices {
    public let writing: any WritingService
    public let styles: any StyleStore
    public let settings: any AppSettingsStore
    public let apiKeys: any APIKeyStore
    public let system: any SystemBridging
    public let updates: (any AppUpdating)?

    public init(
        writing: any WritingService,
        styles: any StyleStore,
        settings: any AppSettingsStore,
        apiKeys: any APIKeyStore,
        system: any SystemBridging,
        updates: (any AppUpdating)? = nil
    ) {
        self.writing = writing
        self.styles = styles
        self.settings = settings
        self.apiKeys = apiKeys
        self.system = system
        self.updates = updates
    }
}
