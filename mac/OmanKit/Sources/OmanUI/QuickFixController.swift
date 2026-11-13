import Foundation
import Observation
import OmanCore
import os

private let quickFixLog = Logger(subsystem: "com.romanbitca.oman", category: "quickfix")

/// Why a quick fix had a corrected text but didn't paste it.
enum QuickFixProblem: Equatable, Sendable {
    /// The selection wasn't the text that was proofread any more.
    case selectionChanged
    /// Another app was in front when the answer was ready. It isn't brought back.
    case movedAway
    /// The app had quit.
    case appGone
    case permissionMissing
    /// The proofread changed most of the words, which a proofread shouldn't, so it waits for a look.
    case changedTooMuch
    /// Pasted text can run as a command in a terminal, where the panel asks for a second press.
    case terminal
}

/// The last quick fix, kept in memory only, so the panel can show it afterwards.
struct QuickFix: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// The corrected text was pasted over the selection.
        case applied
        /// The proofread found nothing to correct, so nothing was pasted.
        case unchanged
        /// There is a corrected text, but it wasn't pasted.
        case notPasted(QuickFixProblem)
        /// The proofread itself failed. `error` is nil for an error that isn't one of the writing errors.
        case failed(message: String, error: WritingError?)
    }

    let date: Date
    let app: SourceApp
    /// The selected text that was proofread.
    let original: String
    /// The corrected text, as it was or would have been pasted. Nil when the proofread failed.
    let corrected: String?
    let request: WritingRequest
    let outcome: Outcome
    /// How many places the proofread changed.
    let changes: Int
    /// The written text as the Spending page counts it.
    let actionID: UUID?
    let removedHiddenCharacters: Bool
}

/// What a click on the menu bar icon does while a quick fix works or its mark shows.
public enum QuickFixClick: Equatable, Sendable {
    /// The quick fix stopped before anything was pasted, and the panel proofreads the same text instead. Nil when
    /// the selection wasn't read yet, so the panel reads it itself.
    case handOver(SelectionCapture?)
    /// The paste is under way and ends in a moment, so the click does nothing.
    case wait
    /// The icon's mark is about the last quick fix, which the panel shows.
    case showLast
}

/// Proofreads the selection and pastes the corrected text back over it, without the panel: Proofread's global
/// shortcut with Quick fix on. The menu bar icon shows how it goes, and the panel can show the last one afterwards.
@MainActor
@Observable
public final class QuickFixController {
    struct Timing {
        /// How long the icon shows its check mark.
        var doneFor = Duration.seconds(3)
        /// How long the icon shows that nothing was selected.
        var nothingSelectedFor = Duration.seconds(2)
    }

    private enum Stage {
        case reading, writing, pasting
    }

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private weak var presenter: (any QuickFixPresenting)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored var timing = Timing()
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private var markTask: Task<Void, Never>?
    @ObservationIgnored private var stage: Stage?
    /// Counts the quick fixes started, so one that was stopped never acts after its wait.
    @ObservationIgnored private var attempt = 0
    /// The selection read for the quick fix that is working, to hand to the panel if the icon is clicked.
    @ObservationIgnored private var capture: SelectionCapture?
    /// Whether the icon's mark is about `last`, so that a click on it shows it.
    @ObservationIgnored private var markShowsLast = false

    public private(set) var status: QuickFixStatus = .idle
    /// The last quick fix, kept until OmanAI quits or the next one ends. Never stored.
    private(set) var last: QuickFix?

    public init(services: AppServices, presenter: any QuickFixPresenting, now: @escaping () -> Date = Date.init) {
        self.services = services
        self.presenter = presenter
        self.now = now
    }

    public var hasLast: Bool { last != nil }

    /// Whether a global shortcut is a quick fix: Proofread's, with Quick fix on in Settings. With the panel holding
    /// the keyboard the panel proofreads instead, as a dictation goes into the panel's field then.
    public static func handles(_ action: ShortcutAction, preferences: AppPreferences, panelHasKeyboard: Bool) -> Bool {
        action == .proofread && preferences.proofreadQuickFix && !panelHasKeyboard
    }

    /// Proofread's shortcut with Quick fix on. A second press while one works does nothing.
    public func start() {
        guard status != .working else { return }
        markTask?.cancel()
        markTask = nil
        markShowsLast = false
        attempt += 1
        let current = attempt
        stage = .reading
        capture = nil
        show(.working)
        task = Task { [weak self] in
            await self?.fix(current)
        }
    }

    /// The panel is opening, or a dictation is starting. A quick fix still working stops before anything is pasted,
    /// and the icon's mark goes. A paste already under way finishes, as it takes a moment.
    public func interrupt() {
        if status == .working {
            if stage != .pasting { stop() }
        } else {
            clearMark()
        }
    }

    /// A click on the menu bar icon. Nil when the click isn't about a quick fix, so it opens the panel as usual.
    public func iconClicked() -> QuickFixClick? {
        switch status {
        case .working:
            if stage == .pasting { return .wait }
            let capture = self.capture
            stop()
            return .handOver(capture)
        case .done, .failed:
            let showsLast = markShowsLast && last != nil
            clearMark()
            return showsLast ? .showLast : nil
        case .nothingSelected:
            clearMark()
            return nil
        case .idle:
            return nil
        }
    }

    // MARK: The fix

    private func fix(_ current: Int) async {
        // Without the permission nothing can be read. The panel's setup says what to do.
        guard services.system.isAccessibilityGranted else {
            needsSetup(current, announcement: "Quick fix needs Accessibility permission. Click OmanAI's menu bar icon.")
            return
        }
        let capture = await services.system.captureSelection()
        guard isCurrent(current) else { return }
        guard let app = capture.app, let text = capture.text else {
            nothingSelected(current)
            return
        }
        self.capture = capture
        stage = .writing

        let preferences = (try? services.settings.preferences()) ?? AppPreferences()
        let model = (try? services.settings.selectedModel()) ?? .default
        let styles = (try? services.styles.loadStyles()) ?? []
        let styleID = TemplateMemory.preselectedStyleID(
            for: app, styles: styles, preferences: preferences, store: services.styles
        )
        // As the panel's Proofread asks it: no context, and the template the app's panel would open on.
        let request = WritingRequest(
            task: .proofread(text: text),
            style: styles.first { $0.id == styleID },
            context: WritingContext(),
            model: model,
            quality: preferences.quality,
            outputLanguage: preferences.outputLanguage,
            customInstructions: preferences.customInstructions
        )
        guard let apiKey = model.isLocal ? "" : loadAPIKey() else {
            if (try? services.apiKeys.hasAPIKey()) == true {
                fail(current, app: app, text: text, request: request, error: WritingError.unreadableAPIKey)
            } else {
                needsSetup(current, announcement: "Quick fix needs your Anthropic API key. Click OmanAI's menu bar icon.")
            }
            return
        }

        var draft = ""
        do {
            for try await delta in services.writing.stream(request, apiKey: apiKey) {
                guard isCurrent(current) else { return }
                draft += delta
            }
        } catch {
            guard isCurrent(current) else { return }
            // A cut-off answer ends here too, so it is never pasted.
            fail(current, app: app, text: text, request: request, error: error)
            return
        }
        guard isCurrent(current) else { return }

        // Exactly what the panel would show and paste.
        let cleaned = ResultCleaner.clean(draft, source: text)
        guard !cleaned.text.trimmed.isEmpty else {
            fail(current, app: app, text: text, request: request, error: WritingError.noOutput)
            return
        }
        let corrected = cleaned.text
        let changes = TextChanges(from: text, to: corrected)
        let actionID = recordAction(model: model, app: app, changes: changes.count)
        func kept(_ outcome: QuickFix.Outcome) -> QuickFix {
            QuickFix(
                date: now(), app: app, original: text, corrected: corrected, request: request, outcome: outcome,
                changes: changes.count, actionID: actionID, removedHiddenCharacters: cleaned.removedHiddenCharacters
            )
        }

        // Nothing to correct: the text stays as it is, with any formatting a plain paste would drop.
        guard changes.count > 0 else {
            settle(current, kept(.unchanged))
            return
        }
        guard !changes.isRewrite else {
            settle(current, kept(.notPasted(.changedTooMuch)))
            return
        }
        guard !SensitiveApps.isTerminal(bundleID: app.bundleID) else {
            settle(current, kept(.notPasted(.terminal)))
            return
        }
        // Someone who moved on to another app meanwhile isn't pulled back to this one.
        guard services.system.frontmostApp?.processID == app.processID else {
            settle(current, kept(.notPasted(.movedAway)))
            return
        }

        stage = .pasting
        // As Replace does: the selection is read again first and nothing is pasted if it changed, and the paste is
        // a ⌘V, so ⌘Z in the app brings back what was there.
        let outcome = await services.system.replaceSelection(expected: text, with: corrected, in: app)
        guard current == attempt else { return }
        switch outcome {
        case .inserted:
            if let actionID {
                try? services.actions?.markActionApplied(id: actionID)
            }
            settle(current, kept(.applied))
        case .selectionChanged, .focusMoved:
            settle(current, kept(.notPasted(.selectionChanged)))
        case .sourceUnavailable:
            settle(current, kept(.notPasted(.appGone)))
        case .permissionMissing:
            settle(current, kept(.notPasted(.permissionMissing)))
        }
    }

    private func isCurrent(_ current: Int) -> Bool {
        current == attempt && stage != nil && !Task.isCancelled
    }

    private func loadAPIKey() -> String? {
        guard let key = try? services.apiKeys.loadAPIKey(), !key.isEmpty else { return nil }
        return key
    }

    /// Notes the proofread for the Spending page and OmanAI's window, as one from the panel is noted. Never the text.
    private func recordAction(model: WritingModel, app: SourceApp, changes: Int) -> UUID? {
        guard let store = services.actions else { return nil }
        let action = WritingAction(date: now(), kind: .proofread, model: model.rawValue, appName: app.name, changes: changes)
        do {
            try store.recordAction(action)
            return action.id
        } catch {
            // A gap in the count is no reason to stop the fix.
            quickFixLog.error("Noting a quick fix failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Ending

    private func fail(_ current: Int, app: SourceApp, text: String, request: WritingRequest, error: any Error) {
        let fix = QuickFix(
            date: now(), app: app, original: text, corrected: nil, request: request,
            outcome: .failed(message: error.localizedDescription, error: error as? WritingError),
            changes: 0, actionID: nil, removedHiddenCharacters: false
        )
        settle(current, fix)
    }

    /// Keeps the quick fix for the panel and shows how it ended: a check mark for a moment when it went in or there
    /// was nothing to correct, and otherwise a mark that stays until the icon is clicked.
    private func settle(_ current: Int, _ fix: QuickFix) {
        guard current == attempt else { return }
        last = fix
        end()
        markShowsLast = true
        let spoken = Self.spoken(fix)
        switch fix.outcome {
        case .applied, .unchanged:
            show(.done, announcement: spoken)
            clearMark(after: timing.doneFor, ifStill: .done)
        case .notPasted, .failed:
            show(.failed, announcement: spoken)
        }
    }

    /// No key, or no permission: nothing is kept, and a click on the icon opens the panel, whose setup says what is
    /// missing.
    private func needsSetup(_ current: Int, announcement: String) {
        guard current == attempt else { return }
        end()
        markShowsLast = false
        show(.failed, announcement: announcement)
    }

    /// A slip rather than a failure: the icon says so for a moment, and the last quick fix stays as it was.
    private func nothingSelected(_ current: Int) {
        guard current == attempt else { return }
        end()
        markShowsLast = false
        show(.nothingSelected, announcement: "Quick fix: select some text first.")
        clearMark(after: timing.nothingSelectedFor, ifStill: .nothingSelected)
    }

    private func stop() {
        attempt += 1
        task?.cancel()
        end()
        markShowsLast = false
        show(.idle)
    }

    private func end() {
        task = nil
        stage = nil
        capture = nil
    }

    private func clearMark() {
        markTask?.cancel()
        markTask = nil
        markShowsLast = false
        if status != .idle, status != .working {
            show(.idle)
        }
    }

    private func clearMark(after delay: Duration, ifStill shown: QuickFixStatus) {
        markTask?.cancel()
        markTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.status == shown else { return }
            self.clearMark()
        }
    }

    private func show(_ status: QuickFixStatus, announcement: String? = nil) {
        self.status = status
        presenter?.showQuickFixStatus(status, announcement: announcement)
    }

    /// What VoiceOver says when a quick fix ends.
    static func spoken(_ fix: QuickFix) -> String {
        switch fix.outcome {
        case .applied:
            fix.changes == 1
                ? "Quick fix put 1 correction in \(fix.app.name)."
                : "Quick fix put \(fix.changes) corrections in \(fix.app.name)."
        case .unchanged:
            "Quick fix found nothing to correct."
        case .notPasted(let problem):
            "Quick fix pasted nothing. \(problem.spoken) Click OmanAI's menu bar icon to see the corrections."
        case .failed(let message, _):
            "Quick fix didn't work. \(message)"
        }
    }
}

extension QuickFix {
    /// The line under the text when the panel shows this quick fix.
    var panelNotice: String {
        let name = app.name
        let time = date.formatted(date: .omitted, time: .shortened)
        var line = switch outcome {
        case .applied:
            "Quick fix put this in \(name) at \(time). Press ⌘Z in \(name) to bring back what you wrote."
        case .unchanged:
            "Quick fix found nothing to correct at \(time), so \(name) was left as it was."
        case .notPasted(let problem):
            problem.panelNotice(app: name)
        case .failed(let message, _):
            message
        }
        if removedHiddenCharacters {
            line += " Hidden characters were removed from this result."
        }
        return line
    }
}

extension QuickFixProblem {
    func panelNotice(app: String) -> String {
        switch self {
        case .selectionChanged:
            "Your selection changed while Quick fix worked, so nothing was pasted. "
                + "Select the text again and press Replace, or use Copy."
        case .movedAway:
            "You had moved on from \(app) when Quick fix finished, so nothing was pasted. "
                + "Select the text again and press Replace, or use Copy."
        case .appGone:
            "\(app) is no longer available, so nothing was pasted. Use Copy instead."
        case .permissionMissing:
            "OmanAI needs Accessibility permission to paste, so nothing was pasted. Use Copy instead."
        case .changedTooMuch:
            "This proofread changed most of your words, so Quick fix didn't put it in without a look. "
                + "Press Replace to put it in, or use Copy."
        case .terminal:
            "Pasted text can run as a command in \(app), so Quick fix didn't paste it. "
                + "Press Replace twice to paste it, or use Copy."
        }
    }

    /// The reason in a few words, for VoiceOver.
    var spoken: String {
        switch self {
        case .selectionChanged: "Your selection changed."
        case .movedAway: "You had moved on to another app."
        case .appGone: "The app is no longer available."
        case .permissionMissing: "OmanAI needs Accessibility permission to paste."
        case .changedTooMuch: "The proofread changed most of your words."
        case .terminal: "Pasted text can run as a command in a terminal."
        }
    }
}
