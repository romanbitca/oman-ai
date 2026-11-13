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

    /// The person's own actions, in the order they were made.
    private(set) var customActions: [CustomAction] = []
    private(set) var customActionError: String?

    var tryItText = ""
    private(set) var tryItResult = ""
    private(set) var tryItError: String?
    private(set) var isTrying = false

    private(set) var preferences = AppPreferences()
    private(set) var preferencesError: String?
    private(set) var recordingAction: ShortcutAction?
    /// The dictation action whose keys held on their own are being recorded, and the most held at once so far.
    private(set) var recordingKeysFor: ShortcutAction?
    private(set) var keysHeld: Set<ModifierKey> = []
    private(set) var failedShortcuts: Set<ShortcutAction> = []
    private(set) var shortcutNotice: String?

    private(set) var installsUpdatesAutomatically = false
    var canUpdate: Bool { services.updates != nil }

    private(set) var spending = SpendingSummary.make(from: [], now: Date(), calendar: .current)
    private(set) var spendingError: String?

    @ObservationIgnored private(set) var dictationTask: Task<Void, Never>?
    @ObservationIgnored private(set) var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadID: UUID?
    /// The part of the Dictation page on show.
    var dictationPage: DictationPage = .model
    /// What each model needs before it can listen, read from the models.
    private(set) var modelStatuses: [DictationModel: DictationModelStatus] = [:]
    /// The languages each model knows, as language codes such as "en".
    private(set) var modelLanguageCodes: [DictationModel: Set<String>] = [:]
    /// The languages the chosen model can listen for.
    private(set) var dictationLanguages: [DictationLanguage] = []
    /// The language the chosen model listens for: the person's choice, or the model's default.
    private(set) var dictationLanguage: DictationLanguage?
    /// The model being downloaded, and how far along, from 0 to 1.
    private(set) var downloadingModel: DictationModel?
    private(set) var downloadProgress: Double?
    private(set) var dictationError: String?
    private(set) var microphoneAccess: MicrophoneAccess = .notDetermined
    /// The microphones the Mac has now, to choose one for dictation.
    private(set) var microphones: [Microphone] = []
    var newDictationWord = ""
    var offersDictation: Bool { services.speech != nil }

    /// The chosen model's state, for its chosen language.
    var dictationStatus: DictationModelStatus? { modelStatuses[preferences.dictationModel] }

    /// The person's languages, as listed in macOS's Language & Region settings, as language codes.
    @ObservationIgnored lazy var personLanguages: [String] = {
        var codes: [String] = []
        for identifier in Locale.preferredLanguages {
            let code = Self.languageCode(identifier)
            if !codes.contains(code) { codes.append(code) }
        }
        return Array(codes.prefix(4))
    }()

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
        failedShortcuts.formUnion(reservedShortcuts)
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
        do {
            customActions = try services.customActions?.loadCustomActions() ?? []
            customActionError = nil
        } catch {
            customActions = []
            customActionError = error.localizedDescription
        }
        reloadSpending()
    }

    private func loadAPIKey() -> String? {
        guard let key = try? services.apiKeys.loadAPIKey(), !key.isEmpty else { return nil }
        return key
    }

    // MARK: Spending

    func reloadSpending(now: Date = Date(), calendar: Calendar = .current) {
        guard let store = services.usage else { return }
        do {
            // Everything ever recorded, because the page has an All time view.
            let entries = try store.usageEntries(since: .distantPast)
            let actions = try services.actions?.actions(since: .distantPast) ?? []
            spending = SpendingSummary.make(from: entries, actions: actions, now: now, calendar: calendar)
            spendingError = nil
        } catch {
            spendingError = error.localizedDescription
        }
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
        microphoneAccess = services.system.microphoneAccess
    }

    // MARK: Dictation

    /// Asks every model what it can do here, and reads the kept transcripts again.
    func reloadDictation() {
        microphoneAccess = services.system.microphoneAccess
        guard let speech = services.speech else { return }
        let preferences = self.preferences
        let chosen = preferences.dictationModel
        dictationTask?.cancel()
        dictationTask = Task { [weak self] in
            let microphones = await speech.microphones()
            self?.microphones = microphones
            var statuses: [DictationModel: DictationModelStatus] = [:]
            var codes: [DictationModel: Set<String>] = [:]
            var chosenLanguages: [DictationLanguage] = []
            var chosenLanguage = DictationLanguage.automatic
            for candidate in DictationModel.allCases {
                let languages = await speech.languages(for: candidate)
                var language: DictationLanguage
                if let saved = preferences.dictationLanguage(for: candidate) {
                    language = saved
                } else {
                    language = await speech.defaultLanguage(for: candidate)
                }
                // A choice the model no longer offers falls back to its default.
                if !languages.isEmpty, !languages.contains(language) {
                    language = await speech.defaultLanguage(for: candidate)
                }
                statuses[candidate] = await speech.status(of: candidate, language: language)
                codes[candidate] = Set(await speech.spokenLanguages(of: candidate).map(Self.languageCode))
                if candidate == chosen {
                    chosenLanguages = languages
                    chosenLanguage = language
                }
            }
            guard let self, !Task.isCancelled, self.preferences.dictationModel == chosen else { return }
            self.modelStatuses = statuses
            self.modelLanguageCodes = codes
            self.dictationLanguages = chosenLanguages
            self.dictationLanguage = chosenLanguage
        }
    }

    static func languageCode(_ identifier: String) -> String {
        Locale(identifier: identifier).language.languageCode?.identifier
            ?? String(identifier.prefix { $0 != "-" && $0 != "_" })
    }

    /// A model that is ready is chosen at once; one still to download is downloaded, then chosen.
    func chooseModel(_ model: DictationModel) {
        switch modelStatuses[model] {
        case .ready, .none:
            setDictationModel(model)
        case .needsDownload:
            if model == .apple {
                setDictationModel(model)
            } else {
                downloadModel(model)
            }
        case .unavailable:
            break
        }
    }

    func setDictationModel(_ model: DictationModel) {
        guard model != preferences.dictationModel else { return }
        dictationError = nil
        dictationLanguages = []
        dictationLanguage = nil
        updatePreferences { $0.dictationModel = model }
        reloadDictation()
        DictationController.prepareChosenModel(services: services)
    }

    func setDictationLanguage(_ language: DictationLanguage) {
        guard language != dictationLanguage else { return }
        dictationError = nil
        updatePreferences { $0.setDictationLanguage(language, for: $0.dictationModel) }
        dictationLanguage = language
        reloadDictation()
        DictationController.prepareChosenModel(services: services)
    }

    /// Downloads a model, or the chosen language of Apple's, and chooses it once it is in place.
    func downloadModel(_ model: DictationModel) {
        guard let speech = services.speech, downloadingModel == nil else { return }
        let language = model == preferences.dictationModel
            ? (dictationLanguage ?? .automatic)
            : (preferences.dictationLanguage(for: model) ?? .automatic)
        let download = UUID()
        downloadID = download
        dictationError = nil
        downloadingModel = model
        downloadProgress = 0
        // Settings lives as long as the app, so holding on to it for the length of a download is fine.
        let report: @Sendable (Double) -> Void = { value in
            Task { @MainActor in self.noteProgress(value, of: download) }
        }
        downloadTask = Task {
            var succeeded = false
            do {
                try await speech.download(model, language: language, progress: report)
                succeeded = true
            } catch is CancellationError {
            } catch {
                if downloadID == download {
                    dictationError = (error as? DictationError)?.message ?? error.localizedDescription
                }
            }
            guard downloadID == download else { return }
            downloadID = nil
            downloadingModel = nil
            downloadProgress = nil
            downloadTask = nil
            if succeeded, model != preferences.dictationModel {
                setDictationModel(model)
            } else {
                reloadDictation()
                if succeeded {
                    DictationController.prepareChosenModel(services: services)
                }
            }
        }
    }

    private func noteProgress(_ value: Double, of download: UUID) {
        guard downloadID == download, let progress = downloadProgress else { return }
        downloadProgress = max(progress, min(value, 1))
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadID = nil
        downloadingModel = nil
        downloadProgress = nil
    }

    /// Deletes a downloaded model's files. Removing the chosen one goes back to Apple's.
    func removeModel(_ model: DictationModel) {
        guard let speech = services.speech, model.isDownloaded else { return }
        dictationTask = Task { [weak self] in
            do {
                try await speech.removeDownload(of: model)
            } catch {
                self?.dictationError = error.localizedDescription
            }
            guard let self else { return }
            if self.preferences.dictationModel == model {
                self.setDictationModel(.apple)
            } else {
                self.reloadDictation()
            }
        }
    }

    func allowMicrophone() {
        guard services.system.microphoneAccess == .notDetermined else {
            services.system.openMicrophoneSettings()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            _ = await self.services.system.requestMicrophoneAccess()
            self.microphoneAccess = self.services.system.microphoneAccess
        }
    }

    /// Adds what was typed, which may be several words split by commas, leaving out ones already there.
    func addDictationWords() {
        let typed = newDictationWord
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        newDictationWord = ""
        guard !typed.isEmpty else { return }
        updatePreferences { preferences in
            for word in typed where !preferences.dictationWords.contains(where: { $0.lowercased() == word.lowercased() }) {
                preferences.dictationWords.append(word)
            }
        }
    }

    func removeDictationWord(_ word: String) {
        updatePreferences { $0.dictationWords.removeAll { $0 == word } }
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
        return "\(samples.count) \(samples.count == 1 ? "message" : "messages"), \(words) \(words == 1 ? "word" : "words")"
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
            registerShortcuts()
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

    /// Proofread's shortcut puts the corrections straight back over the selection, without the panel.
    func setProofreadQuickFix(_ enabled: Bool) {
        updatePreferences { $0.proofreadQuickFix = enabled }
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
        case .explain: "Explain selection"
        case .rewrite: "Rewrite selection"
        case .compose: "Compose"
        case .style(let id): "Rewrite as \(styles.first { $0.id == id }?.displayName ?? "style")"
        case .custom(let id): customActions.first { $0.id == id }?.displayName ?? "Your action"
        case .acceptResult: "Replace or Insert"
        case .copyResult: "Copy result"
        case .tryAgain: "Try again"
        case .toggleOriginal: "Show original or changes"
        case .dictateHold: "Hold to dictate"
        case .dictateLong: "Start or stop a long dictation"
        case .cancelDictation: "Cancel a dictation"
        }
    }

    var globalShortcutActions: [ShortcutAction] {
        ShortcutAction.globalActions + styles.map { .style($0.id) } + customActions.map { .custom($0.id) }
    }

    func startRecording(_ action: ShortcutAction) {
        shortcutNotice = nil
        recordingAction = action
        services.system.suspendGlobalShortcuts()
    }

    func cancelRecording() {
        guard recordingAction != nil else { return }
        recordingAction = nil
        registerShortcuts()
    }

    func finishRecording(with combo: KeyCombo) {
        guard let action = recordingAction else { return }
        recordingAction = nil
        guard !combo.isCopyOrPaste else {
            shortcutNotice = "\(combo.displayString) is how OmanAI copies and pastes, so it can't be a shortcut."
            registerShortcuts()
            return
        }
        assign(combo, to: action)
    }

    func clearShortcut(for action: ShortcutAction) {
        shortcutNotice = nil
        recordingAction = nil
        assign(nil, to: action)
    }

    /// A ⌘C or ⌘V shortcut saved by an earlier version is never registered, so it is listed as one that failed.
    private var reservedShortcuts: Set<ShortcutAction> {
        Set(preferences.shortcuts.compactMap { key, combo in
            combo.isCopyOrPaste ? ShortcutAction(storageKey: key) : nil
        })
    }

    /// The keys held on their own for holding to dictate, or for a long dictation.
    func dictationKeys(for action: ShortcutAction) -> ModifierChord? {
        action == .dictateLong ? preferences.dictationLongKey : preferences.dictationHoldKey
    }

    func setDictationKeys(_ chord: ModifierChord?, for action: ShortcutAction) {
        updatePreferences {
            if action == .dictateLong {
                $0.dictationLongKey = chord
            } else {
                $0.dictationHoldKey = chord
            }
        }
        services.system.watchModifierKeys(preferences.dictationChords)
    }

    /// Starts recording keys held on their own for a dictation action. The keys already chosen stop working
    /// meanwhile, so pressing them starts no dictation.
    func startRecordingKeys(for action: ShortcutAction) {
        cancelRecording()
        recordingKeysFor = action
        keysHeld = []
        services.system.watchModifierKeys([])
    }

    /// The keys held now. The most held at once are kept, and letting them all go records them.
    func keysChanged(to held: Set<ModifierKey>) {
        guard let action = recordingKeysFor else { return }
        if held.isEmpty {
            guard let chord = ModifierChord(keysHeld) else { return }
            recordingKeysFor = nil
            keysHeld = []
            setDictationKeys(chord, for: action)
        } else if held.count >= keysHeld.count {
            keysHeld = held
        }
    }

    func cancelKeyRecording() {
        guard recordingKeysFor != nil else { return }
        recordingKeysFor = nil
        keysHeld = []
        services.system.watchModifierKeys(preferences.dictationChords)
    }

    private func registerShortcuts() {
        failedShortcuts = services.system.registerGlobalShortcuts(preferences.globalShortcuts).union(reservedShortcuts)
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
        registerShortcuts()
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

    // MARK: Your actions

    /// Makes a new action, to be edited in its sheet, and returns its identifier.
    @discardableResult
    func createCustomAction() -> UUID {
        let action = CustomAction(name: "New action")
        customActions.append(action)
        persist(action)
        return action.id
    }

    /// Every change is saved as it is made, as a style's are.
    func updateCustomAction(id: UUID, _ change: (inout CustomAction) -> Void) {
        guard let index = customActions.firstIndex(where: { $0.id == id }) else { return }
        change(&customActions[index])
        persist(customActions[index])
    }

    /// Its shortcut goes with it.
    func deleteCustomAction(id: UUID) {
        do {
            try services.customActions?.deleteCustomAction(id: id)
            customActions.removeAll { $0.id == id }
            customActionError = nil
            if recordingAction == .custom(id) {
                recordingAction = nil
            }
            preferences.setCombo(nil, for: .custom(id))
            savePreferences()
            registerShortcuts()
        } catch {
            customActionError = error.localizedDescription
        }
    }

    private func persist(_ action: CustomAction) {
        do {
            try services.customActions?.saveCustomAction(action)
            customActionError = nil
        } catch {
            customActionError = error.localizedDescription
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
            let isSaved = (try? services.apiKeys.hasAPIKey()) ?? false
            tryItError = (isSaved ? WritingError.unreadableAPIKey : WritingError.missingAPIKey).localizedDescription
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
