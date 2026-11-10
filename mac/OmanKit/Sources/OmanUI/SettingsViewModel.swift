import Foundation
import Observation
import OmanCore

@MainActor
@Observable
public final class SettingsViewModel {
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private(set) var tryTask: Task<Void, Never>?

    private(set) var hasAPIKey = false
    private(set) var isValidatingKey = false
    private(set) var apiKeyError: String?
    var apiKeyDraft = ""

    private(set) var selectedModel: WritingModel = .default
    private(set) var modelError: String?

    private(set) var isAccessibilityGranted = false
    private(set) var isScreenCaptureGranted = false
    private(set) var isLaunchAtLogin = false
    private(set) var launchAtLoginError: String?

    private(set) var styles: [WritingStyle] = []
    private(set) var selectedStyleID: UUID?
    private(set) var styleError: String?
    var newSampleText = ""

    var tryItText = ""
    private(set) var tryItResult = ""
    private(set) var tryItError: String?
    private(set) var isTrying = false

    private(set) var preferences = AppPreferences()
    private(set) var preferencesError: String?
    private(set) var recordingAction: ShortcutAction?
    private(set) var failedShortcuts: Set<ShortcutAction> = []
    private(set) var shortcutNotice: String?

    private(set) var installsUpdatesAutomatically = false
    var canUpdate: Bool { services.updates != nil }

    public init(services: AppServices) {
        self.services = services
    }

    public func reload() {
        hasAPIKey = (try? services.apiKeys.hasAPIKey()) ?? false
        apiKeyDraft = ""
        apiKeyError = nil
        selectedModel = (try? services.settings.selectedModel()) ?? .default
        preferences = (try? services.settings.preferences()) ?? AppPreferences()
        installsUpdatesAutomatically = services.updates?.installsUpdatesAutomatically ?? false
        refreshPermissions()
        do {
            styles = try services.styles.loadStyles()
            styleError = nil
        } catch {
            styles = []
            styleError = error.localizedDescription
        }
        if !styles.contains(where: { $0.id == selectedStyleID }) {
            selectedStyleID = styles.first?.id
        }
    }

    private func loadAPIKey() -> String? {
        guard let key = try? services.apiKeys.loadAPIKey(), !key.isEmpty else { return nil }
        return key
    }

    // MARK: Updates

    func setInstallsUpdatesAutomatically(_ enabled: Bool) {
        services.updates?.installsUpdatesAutomatically = enabled
        installsUpdatesAutomatically = enabled
    }

    func checkForUpdates() {
        services.updates?.checkForUpdates()
    }

    // MARK: General

    func refreshPermissions() {
        isAccessibilityGranted = services.system.isAccessibilityGranted
        isScreenCaptureGranted = services.system.isScreenCaptureGranted
        isLaunchAtLogin = services.system.isLaunchAtLoginEnabled
    }

    func saveAPIKey() async {
        let key = apiKeyDraft.trimmed
        guard !key.isEmpty, !isValidatingKey else { return }
        isValidatingKey = true
        apiKeyError = nil
        defer { isValidatingKey = false }
        do {
            try await services.writing.validate(apiKey: key)
            try services.apiKeys.saveAPIKey(key)
            apiKeyDraft = ""
            hasAPIKey = true
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

    func removeAPIKey() {
        do {
            try services.apiKeys.deleteAPIKey()
            hasAPIKey = false
            apiKeyError = nil
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

    func unavailableReason(for model: WritingModel) -> String? {
        services.writing.unavailableReason(for: model)
    }

    func setModel(_ model: WritingModel) {
        if let reason = unavailableReason(for: model) {
            modelError = reason
            return
        }
        do {
            try services.settings.setSelectedModel(model)
            selectedModel = model
            modelError = nil
        } catch {
            modelError = error.localizedDescription
        }
    }

    func requestAccessibility() {
        services.system.requestAccessibility()
    }

    func requestScreenCapture() {
        services.system.requestScreenCapture()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try services.system.setLaunchAtLogin(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        isLaunchAtLogin = services.system.isLaunchAtLoginEnabled
    }

    // MARK: Styles

    var selectedStyle: WritingStyle? { styles.first { $0.id == selectedStyleID } }

    var sampleSummary: String {
        let samples = selectedStyle?.samples ?? []
        let words = samples.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        return "\(samples.count) \(samples.count == 1 ? "sample" : "samples"), \(words) \(words == 1 ? "word" : "words")"
    }

    func selectStyle(_ id: UUID?) {
        guard id != selectedStyleID else { return }
        tryTask?.cancel()
        tryTask = nil
        selectedStyleID = id
        newSampleText = ""
        tryItText = ""
        tryItResult = ""
        tryItError = nil
        isTrying = false
    }

    func createStyle() {
        let style = WritingStyle(name: "New style")
        styles.append(style)
        persist(style)
        selectStyle(style.id)
    }

    func deleteSelectedStyle() {
        guard let id = selectedStyleID else { return }
        do {
            try services.styles.deleteStyle(id: id)
            styles.removeAll { $0.id == id }
            selectStyle(styles.first?.id)
            styleError = nil
            preferences.setCombo(nil, for: .style(id))
            if preferences.defaultStyleID == id { preferences.defaultStyleID = nil }
            savePreferences()
            failedShortcuts = services.system.registerGlobalShortcuts(preferences.globalShortcuts)
        } catch {
            styleError = error.localizedDescription
        }
    }

    // MARK: Preferences

    func updatePreferences(_ change: (inout AppPreferences) -> Void) {
        change(&preferences)
        savePreferences()
    }

    private func savePreferences() {
        do {
            try services.settings.setPreferences(preferences)
            preferencesError = nil
        } catch {
            preferencesError = error.localizedDescription
        }
    }

    func setAppearance(_ mode: AppearanceMode) {
        updatePreferences { $0.appearance = mode }
        services.system.setAppearance(mode)
    }

    // MARK: Shortcuts

    func title(for action: ShortcutAction) -> String {
        switch action {
        case .openPanel: "Open OmanAI"
        case .proofread: "Proofread selection"
        case .rewrite: "Rewrite selection"
        case .compose: "Compose"
        case .style(let id): "Rewrite as \(styles.first { $0.id == id }?.displayName ?? "style")"
        case .acceptResult: "Replace or Insert"
        case .copyResult: "Copy result"
        case .tryAgain: "Try again"
        case .toggleOriginal: "Show original"
        }
    }

    var globalShortcutActions: [ShortcutAction] {
        ShortcutAction.globalActions + styles.map { .style($0.id) }
    }

    func startRecording(_ action: ShortcutAction) {
        shortcutNotice = nil
        recordingAction = action
        services.system.suspendGlobalShortcuts()
    }

    func cancelRecording() {
        guard recordingAction != nil else { return }
        recordingAction = nil
        failedShortcuts = services.system.registerGlobalShortcuts(preferences.globalShortcuts)
    }

    func finishRecording(with combo: KeyCombo) {
        guard let action = recordingAction else { return }
        recordingAction = nil
        guard !combo.isCopyOrPaste else {
            shortcutNotice = "\(combo.displayString) is how OmanAI copies and pastes, so it can't be a shortcut."
            failedShortcuts = services.system.registerGlobalShortcuts(preferences.globalShortcuts)
            return
        }
        assign(combo, to: action)
    }

    func clearShortcut(for action: ShortcutAction) {
        shortcutNotice = nil
        recordingAction = nil
        assign(nil, to: action)
    }

    private func assign(_ combo: KeyCombo?, to action: ShortcutAction) {
        if let combo,
           let otherKey = preferences.shortcuts.first(where: { $0.value == combo && $0.key != action.storageKey })?.key,
           let other = ShortcutAction(storageKey: otherKey) {
            preferences.setCombo(nil, for: other)
            shortcutNotice = "\(combo.displayString) moved here from \(title(for: other))."
        }
        preferences.setCombo(combo, for: action)
        savePreferences()
        failedShortcuts = services.system.registerGlobalShortcuts(preferences.globalShortcuts)
    }

    func updateName(_ name: String) {
        updateSelectedStyle { $0.name = name }
    }

    func updateNote(_ note: String) {
        updateSelectedStyle { $0.note = note }
    }

    func addSample() {
        let text = newSampleText.trimmed
        guard !text.isEmpty else { return }
        updateSelectedStyle { $0.samples.append(StyleSample(text: text)) }
        newSampleText = ""
    }

    func removeSample(id: UUID) {
        updateSelectedStyle { $0.samples.removeAll { $0.id == id } }
    }

    private func updateSelectedStyle(_ change: (inout WritingStyle) -> Void) {
        guard let index = styles.firstIndex(where: { $0.id == selectedStyleID }) else { return }
        change(&styles[index])
        persist(styles[index])
    }

    private func persist(_ style: WritingStyle) {
        do {
            try services.styles.save(style)
            styleError = nil
        } catch {
            styleError = error.localizedDescription
        }
    }

    // MARK: Try it

    func tryIt() {
        let text = tryItText.trimmed
        guard !text.isEmpty, let style = selectedStyle else { return }
        tryTask?.cancel()
        tryItResult = ""
        tryItError = nil
        let writingModel = (try? services.settings.selectedModel()) ?? .default
        guard let apiKey = writingModel.isLocal ? "" : loadAPIKey() else {
            isTrying = false
            tryItError = WritingError.missingAPIKey.localizedDescription
            return
        }
        let request = WritingRequest(
            task: .rewrite(text: text, instruction: nil),
            style: style,
            model: writingModel,
            quality: preferences.quality,
            outputLanguage: preferences.outputLanguage,
            customInstructions: preferences.customInstructions
        )
        let stream = services.writing.stream(request, apiKey: apiKey)
        isTrying = true
        tryTask = Task { [weak self] in
            do {
                for try await delta in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.tryItResult += delta
                }
                guard let self, !Task.isCancelled else { return }
                self.isTrying = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.tryItResult = ""
                self.tryItError = error.localizedDescription
                self.isTrying = false
            }
        }
    }
}
