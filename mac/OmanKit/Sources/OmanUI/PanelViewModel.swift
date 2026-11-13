import Foundation
import Observation
import OmanCore
import os

private let panelLog = Logger(subsystem: "com.romanbitca.oman", category: "panel")

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
    @ObservationIgnored private var changesCache: (original: String, draft: String, changes: TextChanges)?
    /// Set by the app shell, so the panel's microphone buttons can dictate into its fields.
    @ObservationIgnored public weak var dictation: DictationController?
    @ObservationIgnored private var copiedTask: Task<Void, Never>?
    /// The last text written, as the Spending page counts it, until it is put back or another is written.
    @ObservationIgnored private var actionID: UUID?

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
    /// The person's own actions that can run: those with an instruction.
    private(set) var customActions: [CustomAction] = []

    var contextText = ""
    private(set) var includesMessages = false
    /// The clipboard's text, read at the moment its chip was turned on.
    private(set) var clipboardContext: String?
    private(set) var includeScreen = false
    private(set) var screenshot: ScreenshotAttachment?
    private(set) var screenHint: String?
    private(set) var hasClipboardCandidate = false

    private(set) var draft = ""
    private(set) var notice: String?
    private(set) var errorMessage: String?
    private(set) var offersSettings = false
    /// The panel opened on dictated words rather than a selection. They aren't in the app yet, so a result goes in
    /// at the cursor instead of replacing anything.
    private(set) var isDictated = false
    /// Whether there is a transcript for Copy last transcript, from a dictation or a kept transcript.
    private(set) var hasSavedTranscript = false
    private(set) var copiedTranscript = false
    var showOriginal = false
    /// With changes shown, the words a proofread replaced are struck through beside the new ones.
    var showChanges = false

    public init(services: AppServices, presenter: any PanelPresenting) {
        self.services = services
        self.presenter = presenter
    }

    // MARK: Session

    public func begin(with capture: SelectionCapture, keepPinned: Bool = false) {
        dictation?.panelWillOpen()
        cancelWork()
        self.capture = capture
        session += 1
        actionID = nil
        isDictated = false
        copiedTranscript = false
        hasSavedTranscript = dictation?.lastTranscript() != nil
        instruction = ""
        composePrompt = ""
        adjustment = ""
        contextText = ""
        includesMessages = false
        clipboardContext = nil
        includeScreen = false
        screenshot = nil
        screenHint = nil
        draft = ""
        notice = nil
        errorMessage = nil
        offersSettings = false
        showOriginal = false
        showChanges = false
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
        customActions = ((try? services.customActions?.loadCustomActions()) ?? []).filter { !$0.instruction.trimmed.isEmpty }
        hasClipboardCandidate = services.system.hasClipboardText
        route()
        if preferences.includesScreenByDefault, !usesLocalModel, screen != .setup, capture.app != nil,
           services.system.isScreenCaptureGranted {
            setIncludeScreen(true)
        }
    }

    /// Opens on words just dictated, to proofread or rewrite them before they go in where the cursor is.
    public func begin(withDictatedText text: String, from app: SourceApp?) {
        if let app {
            services.system.rememberFocus(in: app)
        }
        begin(with: SelectionCapture(app: app, text: text))
        isDictated = true
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
                // With nothing selected the shortcut only has the template ready for what is written next.
                selectedStyleID = id
            }
        case .custom(let id):
            guard let action = customActions.first(where: { $0.id == id }) else { return }
            runCustomAction(action)
        case .openPanel, .acceptResult, .copyResult, .tryAgain, .toggleOriginal:
            break
        case .dictateHold, .dictateLong, .cancelDictation:
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
            if offersChanges {
                showChanges.toggle()
            } else {
                guard offersOriginal else { return false }
                showOriginal.toggle()
            }
        default:
            return false
        }
        return true
    }

    public func panelDidClose() {
        dictation?.panelWasReset()
        cancelWork()
    }

    // MARK: Dictation

    /// The field a dictation fills while the panel has the keyboard, or nil on a screen with nowhere to type.
    public var dictationField: PanelField? {
        switch screen {
        case .home: .instruction
        case .compose: .composePrompt
        case .result: isOnlyToRead ? nil : .adjustment
        case .setup, .working, .failed: nil
        }
    }

    func text(in field: PanelField) -> String {
        switch field {
        case .instruction: instruction
        case .composePrompt: composePrompt
        case .adjustment: adjustment
        }
    }

    func setText(_ text: String, in field: PanelField) {
        switch field {
        case .instruction: instruction = text
        case .composePrompt: composePrompt = text
        case .adjustment: adjustment = text
        }
    }

    func showNotice(_ text: String) {
        notice = text
    }

    var hasLastTranscript: Bool { hasSavedTranscript || dictation?.lastText != nil }

    func copyLastTranscript() {
        guard let text = dictation?.lastTranscript() else { return }
        services.system.copyToClipboard(text)
        copiedTranscript = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.copiedTranscript = false
        }
    }

    private func cancelWork() {
        runningTask?.cancel()
        runningTask = nil
        screenTask?.cancel()
        screenTask = nil
        setupPollTask?.cancel()
        setupPollTask = nil
    }

    /// The chip chosen last in this app, As written included. An app nothing was chosen in yet, or one whose
    /// template has since been deleted, starts on the default from Settings.
    private func preselectedStyleID() -> UUID? {
        if preferences.remembersStylePerApp, let choice = try? services.styles.lastStyleChoice(forApp: styleMemoryKey) {
            switch choice {
            case .asWritten:
                return nil
            case .style(let id):
                if styles.contains(where: { $0.id == id }) { return id }
            }
        }
        return styles.first(where: { $0.id == preferences.defaultStyleID })?.id
    }

    /// What an app's choice is kept under: its bundle identifier, its name where it has none, and one key for no
    /// app at all, so that a choice is remembered wherever it is made.
    private var styleMemoryKey: String {
        guard let app = capture.app else { return "none" }
        return app.bundleID ?? "name:\(app.name)"
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
        showChanges = false
        screen = baseScreen
        // Only the screen's name is logged, so a Back that seems to do nothing can be told from one that never arrived.
        panelLog.notice("Back pressed, now on \(String(describing: self.screen), privacy: .public)")
    }

    func contentHeightChanged(_ height: CGFloat) {
        presenter?.setPanelContentHeight(height)
    }

    func togglePin() {
        isPinned.toggle()
        presenter?.setPanelPinned(isPinned)
    }

    func openSettings() {
        presenter?.openSettings()
    }

    // MARK: Writing

    /// Corrects mistakes and nothing else, so it takes no context. The chosen template tells it which habits
    /// with capital letters and punctuation are the person's own and not mistakes.
    func proofread() {
        guard let text = capture.text else { return }
        start(task: .proofread(text: text), style: selectedStyle, context: WritingContext())
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

    /// Runs one of the person's own actions on the selection, as typing its instruction into Describe your change
    /// would: with the chosen template and the context that is switched on. An action whose answer is only read
    /// takes the context but no template, as Explain does, since the answer is for the person and not written as
    /// them.
    func runCustomAction(_ action: CustomAction) {
        guard let text = capture.text else { return }
        let instruction = action.instruction.trimmed
        guard !instruction.isEmpty else { return }
        startWithContext(
            task: .custom(text: text, instruction: instruction, output: action.output),
            style: action.output == .paste ? selectedStyle : nil
        )
    }

    /// Chooses the template the next Proofread, Rewrite or Compose uses, and starts nothing. No template is
    /// As written: the person's own voice, as it shows in what they wrote. The choice is remembered for the app
    /// at once, whether or not anything is then written with it.
    func selectStyle(_ style: WritingStyle?) {
        selectedStyleID = style?.id
        rememberStyleChoice()
    }

    /// A style's global shortcut is an action of its own: it rewrites in that style at once. It is one rewrite and
    /// not a choice, so the chip chosen for the app stays as it was for the next panel.
    func chooseStyleAndRewrite(_ style: WritingStyle) {
        selectedStyleID = style.id
        rewrite()
    }

    func compose() {
        let prompt = composePrompt.trimmed
        guard !prompt.isEmpty else { return }
        startWithContext(task: .compose(request: prompt, selectedText: capture.text), style: selectedStyle)
    }

    /// The chip just chosen is the one this app's next panel opens on: a template, or As written.
    private func rememberStyleChoice() {
        guard preferences.remembersStylePerApp else { return }
        try? services.styles.setLastStyleChoice(StyleChoice(styleID: selectedStyleID), forApp: styleMemoryKey)
    }

    func tryAgain() {
        guard var request = lastRequest else { return }
        if isOnlyToRead {
            // A fresh reading or answer, rather than a variation on the last one.
            perform(request)
            return
        }
        request.refinement = Refinement(currentDraft: draft, adjustment: "Write a different version of this.")
        perform(request)
    }

    func applyAdjustment() {
        let typed = adjustment.trimmed
        guard !typed.isEmpty, !isOnlyToRead, var request = lastRequest else { return }
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

    /// Only what is switched on is sent, and everything switched on is on show in the panel.
    private var currentContext: WritingContext {
        let parts = [includesMessages ? contextText.trimmed : "", clipboardContext?.trimmed ?? ""]
        return WritingContext(pastedText: parts.filter { !$0.isEmpty }.joined(separator: "\n\n"), screenshot: screenshot)
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
        actionID = nil
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
        recordAction()
    }

    /// Notes what was written, with which model and for which app, for the Spending page. Never the text.
    private func recordAction() {
        guard let request = lastRequest, let store = services.actions else { return }
        // For a proofread, how many places it changed, for the window's look at how the person's writing goes.
        var changes: Int?
        if case .proofread(let original) = request.task {
            changes = TextChanges(from: original, to: draft).count
        }
        let action = WritingAction(
            date: Date(), kind: request.task.kind, model: request.model.rawValue, appName: capture.app?.name,
            changes: changes
        )
        do {
            try store.recordAction(action)
            actionID = action.id
        } catch {
            // A gap in the count is no reason to stop the person working.
            panelLog.error("Noting a written text failed: \(error.localizedDescription, privacy: .public)")
        }
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

    /// An explanation, or the answer of an action that says so, is for the person to read, so it is never pasted.
    var isOnlyToRead: Bool {
        lastRequest?.task.isOnlyToRead ?? false
    }

    var primaryActionTitle: String { lastTaskIsCompose || isDictated ? "Insert" : "Replace" }
    var canApplyResult: Bool { capture.app != nil && !isOnlyToRead }

    var originalText: String? {
        switch lastRequest?.task {
        case .proofread(let text), .rewrite(let text, _), .explain(let text), .custom(let text, _, _): text
        default: nil
        }
    }

    /// What a proofread changed in the person's text, worked out on the Mac. Nil for every other task,
    /// and until the whole answer is in.
    var proofreadChanges: TextChanges? {
        guard screen == .result, case .proofread(let original) = lastRequest?.task else { return nil }
        if let cache = changesCache, cache.original == original, cache.draft == draft {
            return cache.changes
        }
        let changes = TextChanges(from: original, to: draft)
        changesCache = (original, draft, changes)
        return changes
    }

    /// The header shows the changes instead of the original. Not when nothing changed, and not when nearly
    /// every word did, because marks would then cover the whole text.
    var offersChanges: Bool {
        guard let changes = proofreadChanges else { return false }
        return changes.count > 0 && !changes.isRewrite
    }

    /// The header offers the original for a rewrite or an explanation, and for a proofread that changed nearly
    /// every word. After any other proofread it offers the changes, which show the original words too.
    var offersOriginal: Bool {
        guard originalText != nil else { return false }
        return proofreadChanges?.isRewrite ?? true
    }

    var proofreadChangesDisplay: ProofreadChanges { preferences.proofreadChanges }

    func applyResult() {
        guard !isOnlyToRead else { return }
        if SensitiveApps.isTerminal(bundleID: capture.app?.bundleID), !terminalPasteConfirmed {
            terminalPasteConfirmed = true
            let app = capture.app?.name ?? "a terminal"
            notice = "Pasted text can run as a command in \(app). "
                + "Press \(primaryActionTitle) again to paste it, or use Copy."
            return
        }
        if lastTaskIsCompose || isDictated {
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
            if let actionID {
                try? services.actions?.markActionApplied(id: actionID)
            }
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

    /// Shows the box for pasted messages and sends what is in it. Off, the box is hidden and nothing in it is
    /// sent, though it is kept in case the chip is turned on again.
    func setIncludesMessages(_ enabled: Bool) {
        includesMessages = enabled
    }

    var includesClipboard: Bool { clipboardContext != nil }

    /// The clipboard is only read here, when the person turns its chip on.
    func setIncludesClipboard(_ enabled: Bool) {
        guard enabled else {
            clipboardContext = nil
            return
        }
        guard let text = services.system.clipboardText(), !text.trimmed.isEmpty else {
            // It was emptied since the panel opened, so there is nothing to offer any more.
            hasClipboardCandidate = false
            return
        }
        clipboardContext = text
    }
}
