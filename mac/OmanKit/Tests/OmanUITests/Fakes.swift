import Foundation
import OmanCore
@testable import OmanUI

struct FakeFailure: LocalizedError, Equatable {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

final class FakeWriting: WritingService, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [WritingRequest] = []
    private var recordedKeys: [String] = []
    private var recordedValidations: [String] = []
    private var scriptedDeltas: [String] = ["Hello", " world"]
    private var scriptedError: Error?
    private var scriptedValidationError: Error?
    private var staysOpen = false

    var requests: [WritingRequest] { lock.withLock { recordedRequests } }
    var keys: [String] { lock.withLock { recordedKeys } }
    var validations: [String] { lock.withLock { recordedValidations } }

    func script(deltas: [String], error: Error? = nil, staysOpen: Bool = false) {
        lock.withLock {
            scriptedDeltas = deltas
            scriptedError = error
            self.staysOpen = staysOpen
        }
    }

    func scriptValidation(error: Error?) {
        lock.withLock { scriptedValidationError = error }
    }

    func stream(_ request: WritingRequest, apiKey: String) -> AsyncThrowingStream<String, Error> {
        let (deltas, error, open) = lock.withLock {
            recordedRequests.append(request)
            recordedKeys.append(apiKey)
            return (scriptedDeltas, scriptedError, staysOpen)
        }
        return AsyncThrowingStream { continuation in
            for delta in deltas {
                continuation.yield(delta)
            }
            guard !open else { return }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func validate(apiKey: String) async throws {
        let error = lock.withLock {
            recordedValidations.append(apiKey)
            return scriptedValidationError
        }
        if let error { throw error }
    }

    private var scriptedUnavailableReason: String?

    func scriptUnavailable(_ reason: String?) {
        lock.withLock { scriptedUnavailableReason = reason }
    }

    func unavailableReason(for model: WritingModel) -> String? {
        model.isLocal ? lock.withLock { scriptedUnavailableReason } : nil
    }
}

final class FakeStyles: StyleStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [WritingStyle] = []
    private var lastByBundle: [String: UUID] = [:]
    private var saveCount = 0

    var styles: [WritingStyle] { lock.withLock { stored } }
    var saves: Int { lock.withLock { saveCount } }

    func seed(_ styles: [WritingStyle]) {
        lock.withLock { stored = styles }
    }

    func loadStyles() throws -> [WritingStyle] {
        lock.withLock { stored }
    }

    func save(_ style: WritingStyle) throws {
        lock.withLock {
            saveCount += 1
            if let index = stored.firstIndex(where: { $0.id == style.id }) {
                stored[index] = style
            } else {
                stored.append(style)
            }
        }
    }

    func deleteStyle(id: UUID) throws {
        lock.withLock { stored.removeAll { $0.id == id } }
    }

    func lastStyleID(forBundleID bundleID: String) throws -> UUID? {
        lock.withLock { lastByBundle[bundleID] }
    }

    func setLastStyleID(_ id: UUID?, forBundleID bundleID: String) throws {
        lock.withLock { lastByBundle[bundleID] = id }
    }
}

final class FakeSettings: AppSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var model: WritingModel = .default
    private var stored = AppPreferences()

    func selectedModel() throws -> WritingModel {
        lock.withLock { model }
    }

    func setSelectedModel(_ model: WritingModel) throws {
        lock.withLock { self.model = model }
    }

    func preferences() throws -> AppPreferences {
        lock.withLock { stored }
    }

    func setPreferences(_ preferences: AppPreferences) throws {
        lock.withLock { stored = preferences }
    }
}

final class FakeKeys: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(key: String?) {
        self.key = key
    }

    var current: String? { lock.withLock { key } }

    func loadAPIKey() throws -> String? {
        lock.withLock { key }
    }

    func saveAPIKey(_ key: String) throws {
        lock.withLock { self.key = key }
    }

    func deleteAPIKey() throws {
        lock.withLock { key = nil }
    }
}

@MainActor
final class FakeSystem: SystemBridging {
    var isAccessibilityGranted = true
    var isScreenCaptureGranted = true
    var isLaunchAtLoginEnabled = false
    var clipboard: String?
    var copied: [String] = []
    var replaceOutcome: InsertOutcome = .inserted
    var insertOutcome: InsertOutcome = .inserted
    var replaceCalls: [(expected: String, text: String, app: SourceApp)] = []
    var insertCalls: [(text: String, app: SourceApp?)] = []
    var accessibilityRequests = 0
    var screenRequests = 0
    var screenshotResult: Result<ScreenshotAttachment, Error> = .success(
        ScreenshotAttachment(jpegData: Data([1, 2, 3]), pixelWidth: 10, pixelHeight: 5)
    )

    func requestAccessibility() { accessibilityRequests += 1 }
    func requestScreenCapture() { screenRequests += 1 }
    func setLaunchAtLogin(_ enabled: Bool) throws { isLaunchAtLoginEnabled = enabled }
    func captureSelection() async -> SelectionCapture { SelectionCapture(app: nil, text: nil) }

    func replaceSelection(expected: String, with text: String, in app: SourceApp) async -> InsertOutcome {
        replaceCalls.append((expected, text, app))
        return replaceOutcome
    }

    func insertAtCursor(_ text: String, in app: SourceApp?) async -> InsertOutcome {
        insertCalls.append((text, app))
        return insertOutcome
    }

    func copyToClipboard(_ text: String) { copied.append(text) }
    func clipboardText() -> String? { clipboard }

    var appearance: AppearanceMode?
    var registered: [ShortcutAction: KeyCombo] = [:]
    var rejected: Set<ShortcutAction> = []
    var suspendCount = 0
    var onGlobalShortcut: (@MainActor (ShortcutAction) -> Void)?

    func setAppearance(_ mode: AppearanceMode) { appearance = mode }

    func registerGlobalShortcuts(_ shortcuts: [ShortcutAction: KeyCombo]) -> Set<ShortcutAction> {
        registered = shortcuts
        return rejected.intersection(shortcuts.keys)
    }

    func suspendGlobalShortcuts() { suspendCount += 1 }

    func captureWindow(of app: SourceApp) async throws -> ScreenshotAttachment {
        try screenshotResult.get()
    }
}

@MainActor
final class FakePresenter: PanelPresenting {
    var hideCount = 0
    var showCount = 0
    var settingsCount = 0
    var pinnedValues: [Bool] = []

    func hidePanel() { hideCount += 1 }
    func showPanel() { showCount += 1 }
    func setPanelPinned(_ pinned: Bool) { pinnedValues.append(pinned) }
    func openSettings() { settingsCount += 1 }
}

@MainActor
final class FakeUpdates: AppUpdating {
    var installsUpdatesAutomatically = true
    private(set) var checkCount = 0

    func checkForUpdates() { checkCount += 1 }
}

@MainActor
final class Harness {
    let writing = FakeWriting()
    let styles = FakeStyles()
    let settings = FakeSettings()
    let keys: FakeKeys
    let system = FakeSystem()
    let presenter = FakePresenter()
    let updates = FakeUpdates()

    static let slack = SourceApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", processID: 42)

    init(key: String? = "sk-test") {
        keys = FakeKeys(key: key)
    }

    var services: AppServices {
        AppServices(writing: writing, styles: styles, settings: settings, apiKeys: keys, system: system, updates: updates)
    }

    func makePanel() -> PanelViewModel {
        PanelViewModel(services: services, presenter: presenter)
    }

    func makeSettings() -> SettingsViewModel {
        SettingsViewModel(services: services)
    }
}

@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
