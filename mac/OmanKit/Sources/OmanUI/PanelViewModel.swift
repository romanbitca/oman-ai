import Foundation
import Observation
import OmanCore

enum PanelScreen: Equatable {
    case setup
    case home
    case compose
    case working
    case result
    case failed
}

@MainActor
@Observable
public final class PanelViewModel {
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private weak var presenter: (any PanelPresenting)?
    @ObservationIgnored private(set) var runningTask: Task<Void, Never>?
    @ObservationIgnored private(set) var screenTask: Task<Void, Never>?
    @ObservationIgnored private var setupPollTask: Task<Void, Never>?
    @ObservationIgnored private var screenBeforeRun: PanelScreen = .compose
    @ObservationIgnored private var draftBeforeRun = ""
    @ObservationIgnored private var baseScreen: PanelScreen = .compose
    @ObservationIgnored private(set) var lastRequest: WritingRequest?
    @ObservationIgnored private var preferences = AppPreferences()
    @ObservationIgnored private var terminalPasteConfirmed = false

    private(set) var screen: PanelScreen = .compose
    private(set) var capture = SelectionCapture(app: nil, text: nil)
    private(set) var session = 0
    private(set) var isPinned = false
    private(set) var selectedModel: WritingModel = .default

    private(set) var hasAPIKey = false
    private(set) var isAccessibilityGranted = false
    private(set) var isValidatingKey = false
    private(set) var setupError: String?
    var apiKeyDraft = ""

    var instruction = ""
    var composePrompt = ""
    var adjustment = ""

    private(set) var styles: [WritingStyle] = []
    private(set) var selectedStyleID: UUID?

    var contextText = ""
    var isContextExpanded = false
    private(set) var includeScreen = false
    private(set) var screenshot: ScreenshotAttachment?
    private(set) var screenHint: String?
    private(set) var hasClipboardCandidate = false

    private(set) var draft = ""
    private(set) var notice: String?
    private(set) var errorMessage: String?
    private(set) var offersSettings = false
    var showOriginal = false

    public init(services: AppServices, presenter: any PanelPresenting) {
        self.services = services
        self.presenter = presenter
    }

    // MARK: Session

    public func begin(with capture: SelectionCapture, keepPinned: Bool = false) {
        cancelWork()
        self.capture = capture
        session += 1
        instruction = ""
        composePrompt = ""
        adjustment = ""
        contextText = ""
        isContextExpanded = false
        includeScreen = false
        screenshot = nil
        screenHint = nil
        draft = ""
        notice = nil
        errorMessage = nil
        offersSettings = false
        showOriginal = false
        lastRequest = nil
        terminalPasteConfirmed = false
        apiKeyDraft = ""
        setupError = nil
        preferences = (try? services.settings.preferences()) ?? AppPreferences()
        selectedModel = (try? services.settings.selectedModel()) ?? .default
        isPinned = keepPinned || preferences.keepsPanelOpen
        presenter?.setPanelPinned(isPinned)
        styles = (try? services.styles.loadStyles()) ?? []
        selectedStyleID = preselectedStyleID()
        hasClipboardCandidate = services.system.hasClipboardText
        route()
        if preferences.includesScreenByDefault, !usesLocalModel, screen != .setup, capture.app != nil,
           services.system.isScreenCaptureGranted {
            setIncludeScreen(true)
        }
    }

    /// Carries out a global shortcut right after `begin(with:)`.
    public func run(_ action: ShortcutAction) {
        guard screen == .home || screen == .compose else { return }
        switch action {
        case .proofread:
            proofread()
        case .rewrite:
            rewrite()
        case .explain:
            explain()
        case .compose:
            openCompose()
        case .style(let id):
            guard let style = styles.first(where: { $0.id == id }) else { return }
            if capture.text != nil {
                chooseStyleAndRewrite(style)
            } else {
                selectedStyleID = id
            }
        case .openPanel, .acceptResult, .copyResult, .tryAgain, .toggleOriginal:
            break
        }
    }

    /// Returns true when the key combination belongs to a result action, so it should not reach the text fields.
    public func handlePanelShortcut(_ combo: KeyCombo) -> Bool {
        guard screen == .result,
              let action = ShortcutAction.panelActions.first(where: { preferences.combo(for: $0) == combo })
        else { return false }
        switch action {
        case .acceptResult:
            guard canApplyResult else { return false }
            applyResult()
        case .copyResult:
            copyResult()
        case .tryAgain:
            tryAgain()
        case .toggleOriginal:
            guard originalText != nil else { return false }
            showOriginal.toggle()
        default:
            return false
        }
        return true
    }

    public func panelDidClose() {
        cancelWork()
    }

    private func cancelWork() {
        runningTask?.cancel()
        runningTask = nil
        screenTask?.cancel()
        screenTask = nil
        setupPollTask?.cancel()
        setupPollTask = nil
    }

    private func preselectedStyleID() -> UUID? {
        if preferences.remembersStylePerApp,
           let bundleID = capture.app?.bundleID,
           let stored = try? services.styles.lastStyleID(forBundleID: bundleID),
           styles.contains(where: { $0.id == stored }) {
            return stored
        }
        return styles.first(where: { $0.id == preferences.defaultStyleID })?.id
    }

    private func loadAPIKey() -> String? {
        guard let key = try? services.apiKeys.loadAPIKey(), !key.isEmpty else { return nil }
        return key
    }

    private func route() {
        hasAPIKey = (try? services.apiKeys.hasAPIKey()) ?? false
        isAccessibilityGranted = services.system.isAccessibilityGranted
        guard isKeyStepDone, isAccessibilityGranted else {
            screen = .setup
            startSetupPolling()
            return
        }
        let destination: PanelScreen = capture.text != nil ? .home : .compose
        baseScreen = destination
        screen = destination
    }

    // MARK: Setup

    private func startSetupPolling() {
        guard setupPollTask == nil else { return }
        setupPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.refreshSetup()
            }
        }
    }

    func refreshSetup() {
        guard screen == .setup else { return }
        isAccessibilityGranted = services.system.isAccessibilityGranted
        guard isKeyStepDone, isAccessibilityGranted else { return }
        setupPollTask?.cancel()
        setupPollTask = nil
        if isPinned {
            isPinned = false
            presenter?.setPanelPinned(false)
        }
        route()
    }

    func saveSetupKey() async {
        let key = apiKeyDraft.trimmed
        guard !key.isEmpty, !isValidatingKey else { return }
        isValidatingKey = true
        setupError = nil
        defer { isValidatingKey = false }
        do {
            try await services.writing.validate(apiKey: key)
            try services.apiKeys.saveAPIKey(key)
            apiKeyDraft = ""
            hasAPIKey = true
            refreshSetup()
        } catch {
            setupError = error.localizedDescription
        }
    }

    var usesLocalModel: Bool { selectedModel.isLocal }
    var isKeyStepDone: Bool { hasAPIKey || usesLocalModel }
    var canUseAppleModel: Bool { services.writing.unavailableReason(for: .appleOnDevice) == nil }

    func useAppleModel() {
        try? services.settings.setSelectedModel(.appleOnDevice)
        selectedModel = .appleOnDevice
        setupError = nil
        refreshSetup()
    }

    func allowAccessibility() {
        // Going to System Settings is an outside click; pinning keeps the setup screen and its polling alive.
        isPinned = true
        presenter?.setPanelPinned(true)
        services.system.requestAccessibility()
    }

    // MARK: Navigation

    var sourceAppName: String? { capture.app?.name }
    var canGoBackFromCompose: Bool { capture.text != nil }
    var canCompose: Bool { !composePrompt.trimmed.isEmpty }
    var selectedStyle: WritingStyle? { styles.first { $0.id == selectedStyleID } }

    func openCompose() {
        baseScreen = .compose
        screen = .compose
    }

    func backToHome() {
        baseScreen = .home
        screen = .home
    }

    func goBack() {
        draft = ""
        notice = nil
        errorMessage = nil
        offersSettings = false
        adjustment = ""
        showOriginal = false
        screen = baseScreen
    }

    func togglePin() {
        isPinned.toggle()
        presenter?.setPanelPinned(isPinned)
    }

    func openSettings() {
        presenter?.openSettings()
    }

    // MARK: Writing

    func proofread() {
        guard let text = capture.text else { return }
        start(task: .proofread(text: text), style: nil, context: WritingContext())
    }

    func rewrite() {
        guard let text = capture.text else { return }
        let typed = instruction.trimmed
        startWithContext(task: .rewrite(text: text, instruction: typed.isEmpty ? nil : typed), style: selectedStyle)
    }

    /// Asks how a reader will understand the selection, with the same context a rewrite would get.
    func explain() {
        guard let text = capture.text else { return }
        startWithContext(task: .explain(text: text), style: nil)
    }

    func chooseStyleAndRewrite(_ style: WritingStyle) {
        selectedStyleID = style.id
        if preferences.remembersStylePerApp, let bundleID = capture.app?.bundleID {
            try? services.styles.setLastStyleID(style.id, forBundleID: bundleID)
        }
        rewrite()
    }

    func toggleComposeStyle(_ style: WritingStyle) {
        selectedStyleID = selectedStyleID == style.id ? nil : style.id
    }

    func compose() {
        let prompt = composePrompt.trimmed
        guard !prompt.isEmpty else { return }
        startWithContext(task: .compose(request: prompt, selectedText: capture.text), style: selectedStyle)
    }

    func tryAgain() {
        guard var request = lastRequest else { return }
        if isExplanation {
            // A fresh reading, rather than a variation on the last one.
            perform(request)
            return
        }
        request.refinement = Refinement(currentDraft: draft, adjustment: "Write a different version of this.")
        perform(request)
    }

    func applyAdjustment() {
        let typed = adjustment.trimmed
        guard !typed.isEmpty, !isExplanation, var request = lastRequest else { return }
        request.refinement = Refinement(currentDraft: draft, adjustment: typed)
        adjustment = ""
        perform(request)
    }

    func retryFailed() {
        guard let lastRequest else { return }
        perform(lastRequest)
    }

    func stop() {
        runningTask?.cancel()
        runningTask = nil
        draft = draftBeforeRun
        screen = screenBeforeRun
    }

    private var currentContext: WritingContext {
        WritingContext(pastedText: contextText, screenshot: screenshot)
    }

    /// Rewrite and Compose send the context. When the screen was asked for and its capture is still running,
    /// the request waits for the picture instead of leaving without it.
    private func startWithContext(task: WritingTask, style: WritingStyle?) {
        guard includeScreen, screenshot == nil, let pendingCapture = screenTask else {
            start(task: task, style: style, context: currentContext)
            return
        }
        runningTask?.cancel()
        rememberScreenBeforeRun()
        notice = nil
        errorMessage = nil
        draft = ""
        screen = .working
        runningTask = Task { [weak self] in
            await pendingCapture.value
            guard let self, !Task.isCancelled else { return }
            guard self.screenshot != nil else {
                // The capture failed and says why beside the Screen chip, so go back there rather than send without it.
                self.draft = self.draftBeforeRun
                self.screen = self.screenBeforeRun
                return
            }
            self.start(task: task, style: style, context: self.currentContext)
        }
    }

    private func rememberScreenBeforeRun() {
        if screen != .working, screen != .failed {
            screenBeforeRun = screen
            draftBeforeRun = draft
        }
    }

    private func start(task: WritingTask, style: WritingStyle?, context: WritingContext) {
        let model = (try? services.settings.selectedModel()) ?? .default
        perform(
            WritingRequest(
                task: task,
                style: style,
                context: context,
                model: model,
                quality: preferences.quality,
                outputLanguage: preferences.outputLanguage,
                customInstructions: preferences.customInstructions
            )
        )
    }

    private func perform(_ request: WritingRequest) {
        runningTask?.cancel()
        lastRequest = request
        notice = nil
        errorMessage = nil
        offersSettings = false
        showOriginal = false
        terminalPasteConfirmed = false
        rememberScreenBeforeRun()
        guard let apiKey = request.model.isLocal ? "" : loadAPIKey() else {
            let isSaved = (try? services.apiKeys.hasAPIKey()) ?? false
            fail(with: isSaved ? WritingError.unreadableAPIKey : WritingError.missingAPIKey)
            return
        }
        draft = ""
        screen = .working
        let stream = services.writing.stream(request, apiKey: apiKey)
        runningTask = Task { [weak self] in
            do {
                for try await delta in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.draft += delta
                }
                guard let self, !Task.isCancelled else { return }
                self.showResult()
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.fail(with: error)
            }
        }
    }

    /// What the panel shows is exactly what Replace, Insert and Copy will deliver.
    private func showResult() {
        let cleaned = ResultCleaner.clean(draft, source: originalText)
        guard !cleaned.text.trimmed.isEmpty else {
            fail(with: WritingError.noOutput)
            return
        }
        draft = cleaned.text
        if cleaned.removedHiddenCharacters {
            notice = "Hidden characters were removed from this result."
        }
        screen = .result
    }

    private func fail(with error: Error) {
        draft = ""
        errorMessage = error.localizedDescription
        let writingError = error as? WritingError
        offersSettings = [.missingAPIKey, .unreadableAPIKey, .invalidAPIKey].contains(writingError)
        screen = .failed
    }

    // MARK: Result

    private var lastTaskIsCompose: Bool {
        if case .compose = lastRequest?.task { return true }
        return false
    }

    /// An explanation is for the person to read, so it is never pasted.
    var isExplanation: Bool {
        if case .explain = lastRequest?.task { return true }
        return false
    }

    var primaryActionTitle: String { lastTaskIsCompose ? "Insert" : "Replace" }
    var canApplyResult: Bool { capture.app != nil && !isExplanation }

    var originalText: String? {
        switch lastRequest?.task {
        case .proofread(let text), .rewrite(let text, _), .explain(let text): text
        default: nil
        }
    }

    func applyResult() {
        guard !isExplanation else { return }
        if SensitiveApps.isTerminal(bundleID: capture.app?.bundleID), !terminalPasteConfirmed {
            terminalPasteConfirmed = true
            let app = capture.app?.name ?? "a terminal"
            notice = "Pasted text can run as a command in \(app). "
                + "Press \(primaryActionTitle) again to paste it, or use Copy."
            return
        }
        if lastTaskIsCompose {
            insert()
        } else {
            replace()
        }
    }

    private func replace() {
        guard let expected = capture.text, let app = capture.app else { return }
        let text = draft
        notice = nil
        presenter?.hidePanel()
        runningTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.services.system.replaceSelection(expected: expected, with: text, in: app)
            self.handle(outcome)
        }
    }

    private func insert() {
        guard capture.app != nil else { return }
        let text = draft
        let app = capture.app
        notice = nil
        presenter?.hidePanel()
        runningTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.services.system.insertAtCursor(text, in: app)
            self.handle(outcome)
        }
    }

    private func handle(_ outcome: InsertOutcome) {
        switch outcome {
        case .inserted:
            if isPinned {
                presenter?.showPanel()
                notice = lastTaskIsCompose ? "Inserted" : "Replaced"
            } else {
                panelDidClose()
            }
        case .selectionChanged:
            presenter?.showPanel()
            notice = "Your selection changed. Select the text again and press Replace, or use Copy."
        case .focusMoved:
            presenter?.showPanel()
            notice = "The cursor has moved since you opened OmanAI. "
                + "Press Insert again to put the text where it is now, or use Copy."
        case .sourceUnavailable:
            presenter?.showPanel()
            notice = "\(capture.app?.name ?? "The app") is no longer available. Use Copy instead."
        case .permissionMissing:
            presenter?.showPanel()
            notice = "OmanAI needs Accessibility permission to paste."
        }
    }

    func copyResult() {
        services.system.copyToClipboard(draft)
        notice = "Copied"
    }

    // MARK: Context

    func setIncludeScreen(_ enabled: Bool) {
        screenHint = nil
        screenTask?.cancel()
        screenTask = nil
        guard enabled else {
            includeScreen = false
            screenshot = nil
            return
        }
        guard let app = capture.app else { return }
        guard services.system.isScreenCaptureGranted else {
            services.system.requestScreenCapture()
            includeScreen = false
            screenHint = "Allow Screen Recording for OmanAI in System Settings, then turn this on again."
            return
        }
        includeScreen = true
        screenTask = Task { [weak self] in
            guard let self else { return }
            do {
                let shot = try await self.services.system.captureWindow(of: app)
                guard !Task.isCancelled else { return }
                self.screenshot = shot
            } catch {
                guard !Task.isCancelled else { return }
                self.includeScreen = false
                self.screenHint = error.localizedDescription
            }
        }
    }

    /// The Messages chip stays lit while context will be sent, even with its editor closed.
    var isContextChipOn: Bool { isContextExpanded || !contextText.trimmed.isEmpty }

    /// The clipboard is only read here, when the person asks for it.
    func useClipboard() {
        hasClipboardCandidate = false
        guard let text = services.system.clipboardText() else { return }
        contextText = contextText.isEmpty ? text : contextText + "\n\n" + text
        isContextExpanded = true
    }
}
