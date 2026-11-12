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
}

/// Runs one dictation at a time: from a shortcut, the menu bar icon or a microphone button in the panel, to the
/// words being pasted into the app in front or written into the panel's field.
@MainActor
@Observable
public final class DictationController {
    static let escape = KeyCombo(keyCode: 53, modifiers: 0)
    /// How long a sentence about a problem stays on screen.
    static let noticeDuration = Duration.seconds(4)

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
    @ObservationIgnored private var keepsDictations = true
    @ObservationIgnored private var words: [String] = []
    @ObservationIgnored private var removesFillers = true
    @ObservationIgnored private var unloadAfter: TimeInterval?
    @ObservationIgnored private var model: DictationModel = .default
    @ObservationIgnored private var language: DictationLanguage = .automatic

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

    public init(services: AppServices, presenter: any DictationPresenting, now: @escaping () -> Date = Date.init) {
        self.services = services
        self.presenter = presenter
        self.now = now
    }

    public var isActive: Bool { phase != .idle }

    // MARK: Starting and finishing

    /// `field` is the panel's field when the panel has the keyboard, so the words go there instead of the app.
    public func holdPressed(into field: PanelField?) {
        guard phase == .idle else { return }
        start(.hold, into: field)
    }

    public func holdReleased() {
        guard mode == .hold else { return }
        finish()
    }

    public func longPressed(into field: PanelField?) {
        switch phase {
        case .idle:
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

    /// The microphone button beside one of the panel's fields.
    public func toggle(into field: PanelField) {
        if phase == .idle {
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

    private func start(_ mode: DictationMode, into field: PanelField?) {
        noticeTask?.cancel()
        notice = nil
        self.mode = mode
        self.field = field
        transcript = LiveTranscript()
        level = 0
        finishWhenStarted = false
        startedAt = nil
        phase = .starting

        let preferences = (try? services.settings.preferences()) ?? AppPreferences()
        position = preferences.dictationPillPosition
        pillStyle = preferences.dictationPillStyle
        model = preferences.dictationModel
        keepsDictations = preferences.keepsDictations
        words = preferences.dictationWords
        removesFillers = preferences.removesFillerWords
        unloadAfter = preferences.modelUnloadDelay.seconds
        targetApp = field == nil ? services.system.frontmostApp : nil
        panelBase = field.flatMap { panel?.text(in: $0) } ?? ""

        services.system.setTemporaryShortcut(Self.escape, for: .cancelDictation)
        presenter?.setDictationActive(true)
        if field == nil {
            presenter?.showDictationPill(at: position)
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
            let session = try await speech.startSession(model: model, language: language, words: words)
            guard phase == .starting, !Task.isCancelled else {
                await session.cancel()
                return
            }
            self.session = session
            startedAt = now()
            listeningSince = startedAt
            phase = .listening
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
        case .idle, .finishing:
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
        if let field, let panel {
            panel.setText(LiveTranscript.join(panelBase, text), in: field)
            save(text, duration: duration, appName: "OmanAI")
            end()
            return
        }

        let outcome = await services.system.insertAtCursor(text, in: nil)
        save(text, duration: duration, appName: targetApp?.name)
        guard phase == .finishing else { return }
        switch outcome {
        case .inserted:
            end()
        case .permissionMissing:
            services.system.copyToClipboard(text)
            end(notice: "OmanAI needs Accessibility to paste. Your words were copied instead.")
        case .selectionChanged, .focusMoved, .sourceUnavailable:
            services.system.copyToClipboard(text)
            end(notice: "There was nowhere to paste, so your words were copied.")
        }
    }

    private func save(_ text: String, duration: TimeInterval, appName: String?) {
        guard keepsDictations, let store = services.dictations else { return }
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

    /// Back to idle. With a notice, the sentence stays on screen for a moment.
    private func end(notice message: String? = nil) {
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
    case model, look, words, transcripts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .model: "Model"
        case .look: "Look"
        case .words: "Words"
        case .transcripts: "Transcripts"
        }
    }
}
