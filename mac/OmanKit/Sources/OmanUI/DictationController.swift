import Foundation
import Observation
import OmanCore
import os

private let dictationLog = Logger(subsystem: "com.romanbitca.oman", category: "dictation")

/// A text field in the panel that a dictation can fill.
public enum PanelField: Equatable, Sendable {
    case instruction
    case composePrompt
    case adjustment
}

public enum DictationMode: Equatable, Sendable {
    /// The shortcut is held down while the person speaks, and letting go puts the words in.
    case hold
    /// Started and finished by pressing the other shortcut, or by a click.
    case long
}

public enum DictationPhase: Equatable, Sendable {
    case idle
    /// Checking the microphone and loading the model.
    case starting
    case listening
    /// Listening has stopped, and the model is settling the last words before they go in.
    case finishing
    /// The words are ready, but nothing that takes text had the cursor. They wait in the pill until a field gets it,
    /// Copy, × or Escape is pressed, or a minute passes.
    case holding
}

/// Runs one dictation at a time: from a shortcut, the menu bar icon or a microphone button in the panel, to the
/// words being pasted into the app in front or written into the panel's field.
@MainActor
@Observable
public final class DictationController {
    static let escape = KeyCombo(keyCode: 53, modifiers: 0)
    /// How long a sentence about a problem stays on screen.
    static let noticeDuration = Duration.seconds(4)
    /// Between the paste and Return, so an app that pastes a moment late has the words before it sends.
    static let submitDelay = Duration.milliseconds(150)
    static let copiedNotice = "There was nowhere to paste, so your words were copied."
    static let waitedNotice = "No field was chosen, so your words were copied."

    /// While words wait for a field: how often the app in front is asked what has the cursor, and how long the words
    /// wait before they are copied instead.
    struct HoldTiming {
        var checkEvery = Duration.milliseconds(250)
        var giveUpAfter = Duration.seconds(60)
    }

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private weak var presenter: (any DictationPresenting)?
    @ObservationIgnored public weak var panel: PanelViewModel?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var session: (any DictationSession)?
    @ObservationIgnored private(set) var startTask: Task<Void, Never>?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private(set) var finishTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var finishWhenStarted = false
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var panelBase = ""
    @ObservationIgnored private var targetApp: SourceApp?
    @ObservationIgnored private var history: DictationHistory = .all
    @ObservationIgnored private var preferences = AppPreferences()
    /// The words go to the panel to be proofread or rewritten, rather than straight into the app.
    @ObservationIgnored private var improvesAfter = false
    @ObservationIgnored private var mutedOutput = false
    @ObservationIgnored private var words: [String] = []
    @ObservationIgnored private var removesFillers = true
    @ObservationIgnored private var unloadAfter: TimeInterval?
    @ObservationIgnored private var model: DictationModel = .default
    @ObservationIgnored private var language: DictationLanguage = .automatic
    @ObservationIgnored var holdTiming = HoldTiming()
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    /// The words waiting for a field, without the space Settings may add after them.
    @ObservationIgnored private var heldText: String?

    public private(set) var phase: DictationPhase = .idle
    public private(set) var mode: DictationMode?
    /// The panel's field the words go to, or nil for the app in front.
    public private(set) var field: PanelField?
    public private(set) var transcript = LiveTranscript()
    /// How loud the microphone is, from 0 to 1.
    public private(set) var level: Float = 0
    /// A sentence about a dictation that could not start or finish.
    public private(set) var notice: String?
    public private(set) var position: DictationPillPosition = .menuBar
    public private(set) var pillStyle: DictationPillStyle = .card
    /// When the microphone started listening, for the seconds the pill counts.
    public private(set) var listeningSince: Date?
    /// The model is still loading. The microphone already listens, and its words follow once the model is ready.
    public private(set) var isLoadingModel = false
    public private(set) var modelName = DictationModel.default.displayName
    /// The words of the last dictation put in, for Copy last transcript, whether or not transcripts are kept.
    public private(set) var lastText: String?

    public init(services: AppServices, presenter: any DictationPresenting, now: @escaping () -> Date = Date.init) {
        self.services = services
        self.presenter = presenter
        self.now = now
    }

    /// Listening, or putting the words in. Words waiting for a field don't count: meanwhile the menu bar icon and the
    /// shortcuts work as usual, and copy the words before they start anything.
    public var isActive: Bool { phase != .idle && phase != .holding }

    /// The words of the last dictation: this one's since OmanAI started, or else the newest transcript kept.
    func lastTranscript() -> String? {
        if let lastText { return lastText }
        return (try? services.dictations?.latestDictation())??.text
    }

    // MARK: Starting and finishing

    /// `field` is the panel's field when the panel has the keyboard, so the words go there instead of the app.
    public func holdPressed(into field: PanelField?) {
        guard !isActive else { return }
        start(.hold, into: field)
    }

    public func holdReleased() {
        guard mode == .hold else { return }
        finish()
    }

    public func longPressed(into field: PanelField?) {
        switch phase {
        case .idle, .holding:
            start(.long, into: field)
        case .starting, .listening:
            if mode == .long { finish() }
        case .finishing:
            break
        }
    }

    /// The menu bar icon, or the pill's button: puts in what was said so far.
    public func finishNow() {
        guard phase == .starting || phase == .listening else { return }
        finish()
    }

    /// The pill's ✨ button: finishes, and opens the panel with the words to proofread or rewrite them first.
    public func improveNow() {
        guard field == nil, phase == .starting || phase == .listening else { return }
        improvesAfter = true
        finish()
    }

    /// A tap on a key that both holds and starts a long dictation: it keeps listening after the key comes up.
    func keepListening() {
        guard mode == .hold, phase == .starting || phase == .listening else { return }
        mode = .long
    }

    /// The microphone button beside one of the panel's fields.
    public func toggle(into field: PanelField) {
        if !isActive {
            start(.long, into: field)
        } else if self.field == field {
            finishNow()
        }
    }

    /// Escape, or the pill's close button: stops at once and puts nothing in.
    public func cancel() {
        guard phase != .idle else { return }
        let session = self.session
        startTask?.cancel()
        finishTask?.cancel()
        if let field, let panel {
            panel.setText(panelBase, in: field)
        }
        end()
        if let session {
            Task { await session.cancel() }
        }
    }

    /// The panel closed or started over, so a dictation into one of its fields has nowhere to go.
    public func panelWasReset() {
        if field != nil { cancel() }
    }

    /// The panel is opening. Words waiting for a field are copied, so they are at hand, and the pill goes: under the
    /// menu bar icon it would hang where the panel does.
    public func panelWillOpen() {
        panelWasReset()
        copyHeldWords()
    }

    /// The pill's Copy button, while the words wait for a field: copies them and closes the pill.
    public func copyHeldWords() {
        guard phase == .holding, let heldText else { return }
        services.system.copyToClipboard(heldText)
        end()
    }

    private func start(_ mode: DictationMode, into field: PanelField?) {
        // Words still waiting for a field are copied, so a new dictation never loses them.
        let wasHolding = phase == .holding
        if wasHolding, let heldText {
            services.system.copyToClipboard(heldText)
        }
        holdTask?.cancel()
        holdTask = nil
        heldText = nil
        noticeTask?.cancel()
        notice = nil
        self.mode = mode
        self.field = field
        transcript = LiveTranscript()
        level = 0
        finishWhenStarted = false
        improvesAfter = false
        startedAt = nil
        phase = .starting

        let preferences = (try? services.settings.preferences()) ?? AppPreferences()
        self.preferences = preferences
        position = preferences.dictationPillPosition
        pillStyle = preferences.dictationPillStyle
        model = preferences.dictationModel
        modelName = model.displayName
        isLoadingModel = false
        history = preferences.dictationHistory
        words = preferences.dictationWords
        removesFillers = preferences.removesFillerWords
        unloadAfter = preferences.modelUnloadDelay.seconds
        targetApp = field == nil ? services.system.frontmostApp : nil
        panelBase = field.flatMap { panel?.text(in: $0) } ?? ""

        services.system.setTemporaryShortcut(Self.escape, for: .cancelDictation)
        presenter?.setDictationActive(true)
        if field == nil {
            presenter?.showDictationPill(at: position)
        } else if wasHolding {
            presenter?.hideDictationPill()
        }
        startTask = Task { [weak self] in
            await self?.begin(preferences: preferences)
        }
    }

    private func begin(preferences: AppPreferences) async {
        guard let speech = services.speech else {
            fail(DictationError.unavailable("Dictation isn't part of this build of OmanAI."))
            return
        }
        switch services.system.microphoneAccess {
        case .granted:
            break
        case .notDetermined:
            guard await services.system.requestMicrophoneAccess() else {
                fail(DictationError.microphoneDenied)
                return
            }
        case .denied:
            fail(DictationError.microphoneDenied)
            return
        }
        guard phase == .starting else { return }

        let language: DictationLanguage
        if let chosen = preferences.dictationLanguage(for: model) {
            language = chosen
        } else {
            language = await speech.defaultLanguage(for: model)
        }
        self.language = language
        switch await speech.status(of: model, language: language) {
        case .ready:
            break
        case .needsDownload:
            fail(DictationError.modelNotReady(model))
            return
        case .unavailable(let reason):
            fail(DictationError.unavailable(reason))
            return
        }
        guard phase == .starting else { return }

        do {
            await speech.useMicrophone(preferences.dictationMicrophone)
            let session = try await speech.startSession(model: model, language: language, words: words)
            guard phase == .starting, !Task.isCancelled else {
                await session.cancel()
                return
            }
            self.session = session
            startedAt = now()
            listeningSince = startedAt
            phase = .listening
            if preferences.playsDictationSounds {
                services.system.playSound(.start)
            }
            if preferences.mutesAudioWhileDictating {
                services.system.setOutputMuted(true)
                mutedOutput = true
            }
            updatesTask = Task { [weak self] in
                for await update in session.updates {
                    self?.receive(update)
                }
            }
            if finishWhenStarted {
                finish()
            }
        } catch {
            fail(error)
        }
    }

    private func finish() {
        switch phase {
        case .starting:
            // The shortcut was let go before the microphone was ready. It finishes as soon as it is.
            finishWhenStarted = true
            return
        case .listening:
            break
        case .idle, .finishing, .holding:
            return
        }
        guard let session else { return }
        phase = .finishing
        finishTask = Task { [weak self] in
            do {
                let text = try await session.finish()
                await self?.deliver(text)
            } catch {
                self?.fail(error)
            }
        }
    }

    private func receive(_ update: DictationUpdate) {
        switch update {
        case .transcript(let heard):
            guard phase == .listening || phase == .finishing else { return }
            let live = LiveTranscript(confirmed: tidy(heard.confirmed), tentative: tidy(heard.tentative))
            transcript = live
            if let field, let panel {
                panel.setText(LiveTranscript.join(panelBase, live.text), in: field)
            }
        case .level(let value):
            level = value
        case .loadingModel(let loading):
            isLoadingModel = loading
        }
    }

    /// Loads the chosen model into memory ahead of the next dictation, then lets it be unloaded after the time
    /// Settings gives. Called when the app starts and when the model or its language changes.
    public static func prepareChosenModel(services: AppServices) {
        guard let speech = services.speech else { return }
        let preferences = (try? services.settings.preferences()) ?? AppPreferences()
        guard preferences.modelUnloadDelay != .immediately else { return }
        let model = preferences.dictationModel
        Task {
            let language: DictationLanguage
            if let saved = preferences.dictationLanguage(for: model) {
                language = saved
            } else {
                language = await speech.defaultLanguage(for: model)
            }
            await speech.prepare(model, language: language)
            await speech.unloadModels(after: preferences.modelUnloadDelay.seconds)
        }
    }

    /// Hesitations taken out, if Settings says so, and the person's own words spelled their way.
    private func tidy(_ text: String) -> String {
        let kept = removesFillers ? DictationText.removingFillers(from: text) : text
        return DictationText.applying(words, to: kept)
    }

    private func deliver(_ heard: String) async {
        guard phase == .finishing else { return }
        let text = tidy(heard.trimmingCharacters(in: .whitespacesAndNewlines))
        transcript = LiveTranscript(confirmed: text)
        guard !text.isEmpty else {
            if let field, let panel {
                panel.setText(panelBase, in: field)
            }
            end()
            return
        }
        let duration = startedAt.map { now().timeIntervalSince($0) } ?? 0
        lastText = text
        restoreOutput()
        if preferences.playsDictationSounds {
            services.system.playSound(.finish)
        }
        if let field, let panel {
            panel.setText(LiveTranscript.join(panelBase, text), in: field)
            save(text, duration: duration, appName: "OmanAI")
            end()
            return
        }
        if improvesAfter {
            save(text, duration: duration, appName: targetApp?.name)
            let app = targetApp
            end()
            presenter?.showPanel(withDictatedText: text, from: app)
            return
        }

        // Where nothing takes text, such as on the desktop or in a list, the words wait in the pill for a field
        // instead of being pasted into nowhere. An app that can't say is pasted into as before.
        let focus = await services.system.textFocus()
        // Escape meanwhile: nothing goes in and nothing is kept, as before the paste.
        guard phase == .finishing else { return }
        save(text, duration: duration, appName: targetApp?.name)
        if focus == .cannotTakeText {
            hold(text)
        } else {
            await paste(text)
        }
    }

    /// Pastes the words at the cursor of the app in front, with a space after them and Return if Settings says so.
    private func paste(_ text: String) async {
        let pasted = preferences.addsSpaceAfterDictation ? text + " " : text
        let outcome = await services.system.insertAtCursor(pasted, in: nil)
        guard phase == .finishing else { return }
        switch outcome {
        case .inserted:
            if preferences.dictationSubmit != .off {
                try? await Task.sleep(for: Self.submitDelay)
                // Escape meanwhile means nothing more is pressed.
                guard phase == .finishing else { return }
                services.system.pressReturn(withCommand: preferences.dictationSubmit == .commandReturn)
            }
            end()
        case .permissionMissing:
            services.system.copyToClipboard(text)
            end(notice: "OmanAI needs Accessibility to paste. Your words were copied instead.")
        case .selectionChanged, .focusMoved, .sourceUnavailable:
            services.system.copyToClipboard(text)
            end(notice: Self.copiedNotice)
        }
    }

    /// Keeps the words in the pill and watches for a field to take them. The dictation itself is over, so the menu
    /// bar icon is still again and opens the panel when clicked.
    private func hold(_ text: String) {
        heldText = text
        phase = .holding
        listeningSince = nil
        isLoadingModel = false
        presenter?.setDictationActive(false)
        updatesTask?.cancel()
        updatesTask = nil
        session = nil
        holdTask = Task { [weak self] in
            await self?.waitForField()
        }
    }

    /// Asks the app in front what has the cursor, a few times a second, and pastes the words as soon as a field that
    /// takes text has it, in that app or another. An app that can't say is never pasted into here, since nobody
    /// chose it. After a minute the words are copied instead.
    private func waitForField() async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: holdTiming.giveUpAfter)
        while clock.now < deadline {
            try? await Task.sleep(for: holdTiming.checkEvery)
            guard phase == .holding, !Task.isCancelled else { return }
            if await services.system.textFocus() == .takesText {
                guard phase == .holding, !Task.isCancelled, let heldText else { return }
                phase = .finishing
                await paste(heldText)
                return
            }
        }
        guard phase == .holding, !Task.isCancelled, let heldText else { return }
        services.system.copyToClipboard(heldText)
        end(notice: Self.waitedNotice)
    }

    private func save(_ text: String, duration: TimeInterval, appName: String?) {
        guard history != .off, let store = services.dictations else { return }
        let dictation = SavedDictation(
            date: startedAt ?? now(),
            text: text,
            duration: duration,
            model: model.rawValue,
            language: language.isAutomatic ? nil : language.id,
            appName: appName
        )
        do {
            try store.saveDictation(dictation)
            if let limit = history.limit {
                try store.trimDictations(keepingNewest: limit)
            }
        } catch {
            dictationLog.error("Saving a dictation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fail(_ error: any Error) {
        guard phase != .idle else { return }
        let message = (error as? DictationError)?.message ?? error.localizedDescription
        dictationLog.error("Dictation stopped: \(message, privacy: .public)")
        let session = self.session
        // Words already shown in the panel's field stay there, since they are all the person has.
        end(notice: message)
        if let session {
            Task { await session.cancel() }
        }
    }

    private func restoreOutput() {
        guard mutedOutput else { return }
        services.system.setOutputMuted(false)
        mutedOutput = false
    }

    /// Back to idle. With a notice, the sentence stays on screen for a moment.
    private func end(notice message: String? = nil) {
        holdTask?.cancel()
        holdTask = nil
        heldText = nil
        restoreOutput()
        improvesAfter = false
        services.system.setTemporaryShortcut(nil, for: .cancelDictation)
        if let speech = services.speech {
            let delay = unloadAfter
            Task { await speech.unloadModels(after: delay) }
        }
        presenter?.setDictationActive(false)
        updatesTask?.cancel()
        updatesTask = nil
        session = nil
        startTask = nil
        finishWhenStarted = false
        phase = .idle
        mode = nil
        level = 0
        listeningSince = nil
        isLoadingModel = false

        guard let message else {
            presenter?.hideDictationPill()
            field = nil
            return
        }
        if field != nil, let panel {
            panel.showNotice(message)
            field = nil
            return
        }
        field = nil
        notice = message
        presenter?.showDictationPill(at: position)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noticeDuration)
            guard let self, !Task.isCancelled, self.phase == .idle else { return }
            self.notice = nil
            self.presenter?.hideDictationPill()
        }
    }
}

/// The parts of the Dictation page in Settings.
enum DictationPage: String, CaseIterable, Identifiable {
    case transcripts, model, look, words, sound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcripts: "Transcripts"
        case .model: "Model"
        case .look: "Look"
        case .words: "Words"
        case .sound: "Sound"
        }
    }
}
