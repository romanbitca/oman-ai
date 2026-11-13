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
    private var lastByApp: [String: StyleChoice] = [:]
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

    func lastStyleChoice(forApp key: String) throws -> StyleChoice? {
        lock.withLock { lastByApp[key] }
    }

    func setLastStyleChoice(_ choice: StyleChoice?, forApp key: String) throws {
        lock.withLock { lastByApp[key] = choice }
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

    private var loadCount = 0

    var current: String? { lock.withLock { key } }
    var loads: Int { lock.withLock { loadCount } }

    func hasAPIKey() throws -> Bool {
        lock.withLock { key?.isEmpty == false }
    }

    func loadAPIKey() throws -> String? {
        lock.withLock {
            loadCount += 1
            return key
        }
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

    var microphoneAccess: MicrophoneAccess = .granted
    var microphoneAnswer = true
    var microphoneRequests = 0
    var microphoneSettingsOpened = 0
    var frontmostApp: SourceApp? = Harness.slack

    func requestMicrophoneAccess() async -> Bool {
        microphoneRequests += 1
        microphoneAccess = microphoneAnswer ? .granted : .denied
        return microphoneAnswer
    }

    func openMicrophoneSettings() { microphoneSettingsOpened += 1 }
    func setLaunchAtLogin(_ enabled: Bool) throws { isLaunchAtLoginEnabled = enabled }

    /// What reading the selection finds. Nothing, unless a test says otherwise.
    var selection = SelectionCapture(app: nil, text: nil)
    var captureCount = 0

    func captureSelection() async -> SelectionCapture {
        captureCount += 1
        return selection
    }

    func replaceSelection(expected: String, with text: String, in app: SourceApp) async -> InsertOutcome {
        replaceCalls.append((expected, text, app))
        return replaceOutcome
    }

    func insertAtCursor(_ text: String, in app: SourceApp?) async -> InsertOutcome {
        insertCalls.append((text, app))
        return insertOutcome
    }

    /// What has the cursor in the app in front. A field, unless a test says otherwise.
    var focus: TextFocus = .takesText
    var focusChecks = 0

    func textFocus() async -> TextFocus {
        focusChecks += 1
        return focus
    }

    /// What an app that couldn't say has the cursor in once its accessibility support is on, as an Electron app then
    /// names its field. Nil for one that still can't say.
    var focusOnceSwitchedOn: TextFocus?
    var focusReportingSwitchedOn = 0
    var focusReportingSwitchedOff = 0

    func switchOnFocusReporting() async -> Bool {
        focusReportingSwitchedOn += 1
        if let focusOnceSwitchedOn {
            focus = focusOnceSwitchedOn
        }
        return true
    }

    func switchOffFocusReporting() { focusReportingSwitchedOff += 1 }

    var clipboardReads = 0

    func copyToClipboard(_ text: String) { copied.append(text) }

    var applicationURLs: [String: URL] = [:]
    func applicationURL(named name: String) -> URL? { applicationURLs[name] }
    var hasClipboardText: Bool { clipboard != nil }

    func clipboardText() -> String? {
        clipboardReads += 1
        return clipboard
    }

    var appearance: AppearanceMode?
    var registered: [ShortcutAction: KeyCombo] = [:]
    var rejected: Set<ShortcutAction> = []
    var suspendCount = 0
    var onGlobalShortcut: (@MainActor (ShortcutAction) -> Void)?
    var onGlobalShortcutReleased: (@MainActor (ShortcutAction) -> Void)?
    var temporary: [ShortcutAction: KeyCombo] = [:]

    func setAppearance(_ mode: AppearanceMode) { appearance = mode }

    func registerGlobalShortcuts(_ shortcuts: [ShortcutAction: KeyCombo]) -> Set<ShortcutAction> {
        registered = shortcuts
        return rejected.intersection(shortcuts.keys)
    }

    func suspendGlobalShortcuts() { suspendCount += 1 }

    func setTemporaryShortcut(_ combo: KeyCombo?, for action: ShortcutAction) -> Bool {
        temporary[action] = combo
        return true
    }

    func captureWindow(of app: SourceApp) async throws -> ScreenshotAttachment {
        try screenshotResult.get()
    }

    var onModifierKey: (@MainActor (ModifierKeyEvent) -> Void)?
    var watchedKeys: Set<ModifierChord> = []
    var sounds: [DictationSound] = []
    var mutes: [Bool] = []
    var returnPresses: [Bool] = []
    var focusRemembered: [SourceApp] = []

    func watchModifierKeys(_ chords: Set<ModifierChord>) { watchedKeys = chords }
    func playSound(_ sound: DictationSound) { sounds.append(sound) }
    func setOutputMuted(_ muted: Bool) { mutes.append(muted) }
    func pressReturn(withCommand: Bool) { returnPresses.append(withCommand) }
    func rememberFocus(in app: SourceApp) { focusRemembered.append(app) }
}

@MainActor
final class FakePresenter: PanelPresenting {
    var hideCount = 0
    var showCount = 0
    var settingsCount = 0
    var pinnedValues: [Bool] = []
    var contentHeights: [CGFloat] = []

    func hidePanel() { hideCount += 1 }
    func showPanel() { showCount += 1 }
    func setPanelPinned(_ pinned: Bool) { pinnedValues.append(pinned) }
    func setPanelContentHeight(_ height: CGFloat) { contentHeights.append(height) }
    func openSettings() { settingsCount += 1 }
}

final class FakeUsage: UsageStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [UsageEntry] = []
    private var lastSince: Date?
    private var failure: Error?

    var since: Date? { lock.withLock { lastSince } }

    func seed(_ entries: [UsageEntry]) {
        lock.withLock { stored = entries }
    }

    func fail(with error: Error?) {
        lock.withLock { failure = error }
    }

    func record(_ entry: UsageEntry) throws {
        lock.withLock { stored.append(entry) }
    }

    func usageEntries(since date: Date) throws -> [UsageEntry] {
        try lock.withLock {
            lastSince = date
            if let failure { throw failure }
            return stored.filter { $0.date >= date }.sorted { $0.date < $1.date }
        }
    }
}

@MainActor
final class FakeUpdates: AppUpdating {
    var installsUpdatesAutomatically = true
    private(set) var checkCount = 0

    func checkForUpdates() { checkCount += 1 }
}

final class FakeDictationSession: DictationSession, @unchecked Sendable {
    let updates: AsyncStream<DictationUpdate>
    private let continuation: AsyncStream<DictationUpdate>.Continuation
    private let lock = NSLock()
    private var finalText = ""
    private var finishError: Error?
    private var didFinish = false
    private var didCancel = false

    init() {
        (updates, continuation) = AsyncStream.makeStream(of: DictationUpdate.self)
    }

    var finished: Bool { lock.withLock { didFinish } }
    var cancelled: Bool { lock.withLock { didCancel } }

    func send(_ update: DictationUpdate) {
        continuation.yield(update)
    }

    func willFinish(with text: String, error: Error? = nil) {
        lock.withLock {
            finalText = text
            finishError = error
        }
    }

    func finish() async throws -> String {
        let (text, error) = lock.withLock {
            didFinish = true
            return (finalText, finishError)
        }
        continuation.finish()
        if let error { throw error }
        return text
    }

    func cancel() async {
        lock.withLock { didCancel = true }
        continuation.finish()
    }
}

final class FakeSpeech: SpeechRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [DictationModel: DictationModelStatus] = [:]
    private var startError: Error?
    private var started: [(model: DictationModel, language: DictationLanguage)] = []
    private var made: [FakeDictationSession] = []
    private var downloaded: [DictationModel] = []
    private var removed: [DictationModel] = []
    private var downloadError: Error?

    var languagesByModel: [DictationModel: [DictationLanguage]] = [
        .apple: [DictationLanguage(id: "en-US"), DictationLanguage(id: "ro-RO")],
        .parakeetEnglish: [DictationLanguage(id: "en")],
        .nemotron: [.automatic, DictationLanguage(id: "en"), DictationLanguage(id: "ro"), DictationLanguage(id: "ru")],
        .parakeet: [.automatic, DictationLanguage(id: "en"), DictationLanguage(id: "ro")],
        .whisper: [.automatic, DictationLanguage(id: "en"), DictationLanguage(id: "ro"), DictationLanguage(id: "ja")],
    ]

    var sessions: [FakeDictationSession] { lock.withLock { made } }
    var starts: [(model: DictationModel, language: DictationLanguage)] { lock.withLock { started } }
    var downloads: [DictationModel] { lock.withLock { downloaded } }
    var removals: [DictationModel] { lock.withLock { removed } }

    func setStatus(_ status: DictationModelStatus, for model: DictationModel) {
        lock.withLock { statuses[model] = status }
    }

    func failStart(with error: Error?) {
        lock.withLock { startError = error }
    }

    func failDownload(with error: Error?) {
        lock.withLock { downloadError = error }
    }

    func status(of model: DictationModel, language: DictationLanguage) async -> DictationModelStatus {
        lock.withLock { statuses[model] ?? .ready }
    }

    func languages(for model: DictationModel) async -> [DictationLanguage] {
        languagesByModel[model] ?? []
    }

    func defaultLanguage(for model: DictationModel) async -> DictationLanguage {
        switch model {
        case .apple: DictationLanguage(id: "en-US")
        case .parakeetEnglish: DictationLanguage(id: "en")
        default: .automatic
        }
    }

    func spokenLanguages(of model: DictationModel) async -> [String] {
        switch model {
        case .parakeet, .nemotron: ["en", "ro", "ru"]
        default: (languagesByModel[model] ?? []).filter { !$0.isAutomatic }.map(\.id)
        }
    }

    func download(
        _ model: DictationModel,
        language: DictationLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        progress(0.5)
        try lock.withLock {
            if let downloadError { throw downloadError }
            downloaded.append(model)
            statuses[model] = .ready
        }
        progress(1)
    }

    func removeDownload(of model: DictationModel) async throws {
        lock.withLock {
            removed.append(model)
            statuses[model] = .needsDownload(bytes: 1_000)
        }
    }

    func startSession(
        model: DictationModel,
        language: DictationLanguage,
        words: [String]
    ) async throws -> any DictationSession {
        try lock.withLock {
            if let startError { throw startError }
            let session = FakeDictationSession()
            started.append((model, language))
            startWords.append(words)
            made.append(session)
            return session
        }
    }

    private var startWords: [[String]] = []
    private var unloads: [TimeInterval?] = []
    var wordsGiven: [[String]] { lock.withLock { startWords } }
    var unloadRequests: [TimeInterval?] { lock.withLock { unloads } }

    func unloadModels(after seconds: TimeInterval?) async {
        lock.withLock { unloads.append(seconds) }
    }

    private var prepared: [(DictationModel, DictationLanguage)] = []
    var preparations: [(model: DictationModel, language: DictationLanguage)] { lock.withLock { prepared } }

    func prepare(_ model: DictationModel, language: DictationLanguage) async {
        lock.withLock { prepared.append((model, language)) }
    }

    var availableMicrophones = [Microphone(id: "BuiltIn", name: "MacBook Pro Microphone")]
    private var chosenMicrophones: [String?] = []
    var microphonesUsed: [String?] { lock.withLock { chosenMicrophones } }

    func microphones() async -> [Microphone] { availableMicrophones }

    func useMicrophone(_ id: String?) async {
        lock.withLock { chosenMicrophones.append(id) }
    }
}

final class FakeActions: ActionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [WritingAction] = []
    private var failure: Error?

    var recorded: [WritingAction] { lock.withLock { stored } }

    func seed(_ actions: [WritingAction]) {
        lock.withLock { stored = actions }
    }

    func fail(with error: Error?) {
        lock.withLock { failure = error }
    }

    func recordAction(_ action: WritingAction) throws {
        try lock.withLock {
            if let failure { throw failure }
            stored.append(action)
        }
    }

    func markActionApplied(id: UUID) throws {
        lock.withLock {
            if let index = stored.firstIndex(where: { $0.id == id }) { stored[index].applied = true }
        }
    }

    func actions(since date: Date) throws -> [WritingAction] {
        try lock.withLock {
            if let failure { throw failure }
            return stored.filter { $0.date >= date }.sorted { $0.date < $1.date }
        }
    }
}

final class FakeDictations: DictationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SavedDictation] = []
    private var counted: [DictationCount] = []

    var counts: [DictationCount] { lock.withLock { counted } }

    func seedCounts(_ counts: [DictationCount]) {
        lock.withLock { counted = counts }
    }

    func recordDictationCount(_ count: DictationCount) throws {
        lock.withLock { counted.append(count) }
    }

    func dictationCounts(since date: Date) throws -> [DictationCount] {
        lock.withLock { counted.filter { $0.date >= date }.sorted { $0.date < $1.date } }
    }

    var saved: [SavedDictation] { lock.withLock { stored } }

    func seed(_ dictations: [SavedDictation]) {
        lock.withLock { stored = dictations }
    }

    func saveDictation(_ dictation: SavedDictation) throws {
        lock.withLock { stored.append(dictation) }
    }

    func savedDictations() throws -> [SavedDictation] {
        lock.withLock { stored.sorted { $0.date > $1.date } }
    }

    func latestDictation() throws -> SavedDictation? {
        try savedDictations().first
    }

    func deleteDictation(id: UUID) throws {
        lock.withLock { stored.removeAll { $0.id == id } }
    }

    func deleteAllDictations() throws {
        lock.withLock { stored.removeAll() }
    }

    func trimDictations(keepingNewest count: Int) throws {
        lock.withLock {
            stored = Array(stored.sorted { $0.date > $1.date }.prefix(max(count, 0)))
        }
    }
}

@MainActor
final class FakeDictationPresenter: DictationPresenting {
    var shownAt: [DictationPillPosition] = []
    var hideCount = 0
    var activeValues: [Bool] = []
    var isShowing = false

    func showDictationPill(at position: DictationPillPosition) {
        shownAt.append(position)
        isShowing = true
    }

    func hideDictationPill() {
        hideCount += 1
        isShowing = false
    }

    func setDictationActive(_ active: Bool) { activeValues.append(active) }

    var panelOpenings: [(text: String, app: SourceApp?)] = []

    func showPanel(withDictatedText text: String, from app: SourceApp?) {
        panelOpenings.append((text, app))
    }
}

@MainActor
final class FakeQuickFixPresenter: QuickFixPresenting {
    var statuses: [QuickFixStatus] = []
    var announcements: [String] = []

    func showQuickFixStatus(_ status: QuickFixStatus, announcement: String?) {
        statuses.append(status)
        if let announcement { announcements.append(announcement) }
    }
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
    let usage = FakeUsage()
    let speech = FakeSpeech()
    let dictations = FakeDictations()
    let actions = FakeActions()
    let dictationPresenter = FakeDictationPresenter()
    let quickFixPresenter = FakeQuickFixPresenter()

    static let slack = SourceApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", processID: 42)

    init(key: String? = "sk-test") {
        keys = FakeKeys(key: key)
    }

    var services: AppServices {
        AppServices(
            writing: writing,
            styles: styles,
            settings: settings,
            apiKeys: keys,
            system: system,
            updates: updates,
            usage: usage,
            speech: speech,
            dictations: dictations,
            actions: actions
        )
    }

    /// A dictation controller wired to a panel, as the app shell does it.
    func makeDictation(panel: PanelViewModel? = nil) -> DictationController {
        let controller = DictationController(services: services, presenter: dictationPresenter)
        controller.panel = panel
        panel?.dictation = controller
        return controller
    }

    func makePanel() -> PanelViewModel {
        PanelViewModel(services: services, presenter: presenter)
    }

    /// A quick fix wired to a panel, as the app shell does it.
    func makeQuickFix(panel: PanelViewModel? = nil) -> QuickFixController {
        let controller = QuickFixController(services: services, presenter: quickFixPresenter)
        panel?.quickFix = controller
        return controller
    }

    func makeSettings() -> SettingsViewModel {
        SettingsViewModel(services: services)
    }
}

/// True as soon as the condition holds. The limit is generous because on GitHub's runner every test starts at once
/// in one process, and the main actor can be busy for seconds: at 2 seconds, eleven dictation tests ran out there.
@MainActor
func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Single keys as chords, so tests can write `.rightOption` where a chord is wanted.
extension ModifierChord {
    static let rightOption = ModifierChord(.rightOption)
    static let leftOption = ModifierChord(.leftOption)
    static let rightCommand = ModifierChord(.rightCommand)
    static let leftCommand = ModifierChord(.leftCommand)
}
