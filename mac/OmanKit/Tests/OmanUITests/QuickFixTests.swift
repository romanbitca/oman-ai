import Foundation
import OmanCore
import Testing
@testable import OmanUI

@MainActor
@Suite struct QuickFixTests {
    private let original = "hey can u send it to me tmrw"
    private let corrected = "hey can u send it to me tomorrow"

    private func harness(selecting text: String? = "hey can u send it to me tmrw", answer: [String]? = nil) -> Harness {
        let harness = Harness()
        harness.system.selection = SelectionCapture(app: Harness.slack, text: text)
        harness.writing.script(deltas: answer ?? [corrected])
        return harness
    }

    /// Starts a quick fix and waits for it to end.
    private func run(_ quickFix: QuickFixController) async {
        quickFix.start()
        await quickFix.task?.value
    }

    private func setPreferences(_ harness: Harness, _ change: (inout AppPreferences) -> Void) throws {
        var preferences = try harness.settings.preferences()
        change(&preferences)
        try harness.settings.setPreferences(preferences)
    }

    // MARK: Which shortcut

    @Test func onlyProofreadsShortcutIsAQuickFixAndOnlyWithItOn() {
        var preferences = AppPreferences()
        #expect(!QuickFixController.handles(.proofread, preferences: preferences, panelHasKeyboard: false))
        preferences.proofreadQuickFix = true
        #expect(QuickFixController.handles(.proofread, preferences: preferences, panelHasKeyboard: false))
        // With the panel holding the keyboard the panel proofreads, as before.
        #expect(!QuickFixController.handles(.proofread, preferences: preferences, panelHasKeyboard: true))
        for action: ShortcutAction in [.openPanel, .rewrite, .explain, .compose, .style(UUID()), .dictateHold] {
            #expect(!QuickFixController.handles(action, preferences: preferences, panelHasKeyboard: false))
        }
    }

    @Test func quickFixIsOffUntilItIsTurnedOn() throws {
        #expect(!AppPreferences().proofreadQuickFix)
        let older = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        #expect(!older.proofreadQuickFix)
        var preferences = AppPreferences()
        preferences.proofreadQuickFix = true
        let saved = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(saved.proofreadQuickFix)
    }

    @Test func settingsTurnsQuickFixOnAndOff() throws {
        let harness = Harness()
        let settings = harness.makeSettings()
        settings.reload()
        settings.setProofreadQuickFix(true)
        #expect(settings.preferences.proofreadQuickFix)
        #expect(try harness.settings.preferences().proofreadQuickFix)
        settings.setProofreadQuickFix(false)
        #expect(try !harness.settings.preferences().proofreadQuickFix)
    }

    // MARK: Putting it back

    @Test func aQuickFixProofreadsTheSelectionAndPutsItBack() async throws {
        let harness = harness()
        let quickFix = harness.makeQuickFix()
        await run(quickFix)

        let request = try #require(harness.writing.requests.first)
        #expect(request.task == .proofread(text: original))
        #expect(request.context == WritingContext())
        #expect(request.style == nil)
        let call = try #require(harness.system.replaceCalls.first)
        #expect(call.expected == original)
        #expect(call.text == corrected)
        #expect(call.app == Harness.slack)
        #expect(harness.presenter.showCount == 0)
        #expect(harness.quickFixPresenter.statuses == [.working, .done])
        #expect(harness.quickFixPresenter.announcements == ["Quick fix put 1 correction in Slack."])
        #expect(quickFix.last?.outcome == .applied)
        let action = try #require(harness.actions.recorded.first)
        #expect(action.kind == .proofread)
        #expect(action.appName == "Slack")
        #expect(action.changes == 1)
        #expect(action.applied)
    }

    @Test func theModelAndQualityComeFromSettings() async throws {
        let harness = harness()
        try harness.settings.setSelectedModel(.sonnet)
        try setPreferences(harness) { $0.quality = .best }
        await run(harness.makeQuickFix())
        let request = try #require(harness.writing.requests.first)
        #expect(request.model == .sonnet)
        #expect(request.quality == .best)
    }

    @Test func theTemplateChosenInTheAppIsUsed() async throws {
        let harness = harness()
        let email = WritingStyle(name: "Email")
        let slack = WritingStyle(name: "Slack", samples: [StyleSample(text: "yo")])
        harness.styles.seed([email, slack])
        try setPreferences(harness) { $0.defaultStyleID = email.id }
        try harness.styles.setLastStyleChoice(.style(slack.id), forApp: "com.tinyspeck.slackmacgap")
        await run(harness.makeQuickFix())
        #expect(harness.writing.requests.first?.style == slack)
    }

    @Test func anAppWithNothingChosenUsesTheDefaultTemplate() async throws {
        let harness = harness()
        let email = WritingStyle(name: "Email")
        harness.styles.seed([email])
        try setPreferences(harness) { $0.defaultStyleID = email.id }
        await run(harness.makeQuickFix())
        #expect(harness.writing.requests.first?.style == email)
    }

    @Test func asWrittenChosenInTheAppSendsNoTemplate() async throws {
        let harness = harness()
        let email = WritingStyle(name: "Email")
        harness.styles.seed([email])
        try setPreferences(harness) { $0.defaultStyleID = email.id }
        try harness.styles.setLastStyleChoice(.asWritten, forApp: "com.tinyspeck.slackmacgap")
        await run(harness.makeQuickFix())
        #expect(try #require(harness.writing.requests.first).style == nil)
    }

    @Test func appleModelNeedsNoKey() async throws {
        let harness = Harness(key: nil)
        harness.system.selection = SelectionCapture(app: Harness.slack, text: original)
        harness.writing.script(deltas: [corrected])
        try harness.settings.setSelectedModel(.appleOnDevice)
        await run(harness.makeQuickFix())
        #expect(harness.writing.keys == [""])
        #expect(harness.system.replaceCalls.count == 1)
    }

    @Test func whatIsPastedIsCleanedAsThePanelCleansIt() async throws {
        let harness = harness(answer: [corrected + "\u{200B}\n"])
        let panel = harness.makePanel()
        let quickFix = harness.makeQuickFix(panel: panel)
        await run(quickFix)
        #expect(try #require(harness.system.replaceCalls.first).text == corrected)
        panel.showLastQuickFix()
        #expect(panel.notice?.hasSuffix("Hidden characters were removed from this result.") == true)
    }

    // MARK: When nothing is pasted

    @Test func withNothingSelectedNothingIsAskedOrPasted() async {
        let harness = harness(selecting: nil)
        let quickFix = harness.makeQuickFix()
        quickFix.timing.nothingSelectedFor = .milliseconds(20)
        await run(quickFix)
        #expect(harness.writing.requests.isEmpty)
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(quickFix.last == nil)
        #expect(harness.quickFixPresenter.announcements == ["Quick fix: select some text first."])
        #expect(await eventually { quickFix.status == .idle })
        #expect(harness.quickFixPresenter.statuses == [.working, .nothingSelected, .idle])
    }

    @Test func aSlipKeepsTheLastQuickFix() async {
        let harness = harness()
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        harness.system.selection = SelectionCapture(app: Harness.slack, text: nil)
        await run(quickFix)
        #expect(quickFix.status == .nothingSelected)
        #expect(quickFix.last?.corrected == corrected)
        // The mark is about nothing kept, so a click opens the panel as usual.
        #expect(quickFix.iconClicked() == nil)
        #expect(quickFix.status == .idle)
    }

    @Test(arguments: ["hey can u send it to me tmrw", "hey can u  send it to me tmrw"])
    func aProofreadWithNothingToCorrectPastesNothing(answer: String) async throws {
        let harness = harness(answer: [answer])
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(quickFix.status == .done)
        #expect(quickFix.last?.outcome == .unchanged)
        #expect(harness.quickFixPresenter.announcements == ["Quick fix found nothing to correct."])
        let action = try #require(harness.actions.recorded.first)
        #expect(action.changes == 0)
        #expect(!action.applied)
    }

    @Test func aChangedSelectionIsNotPastedOver() async throws {
        let harness = harness()
        harness.system.replaceOutcome = .selectionChanged
        let quickFix = harness.makeQuickFix()
        quickFix.timing.doneFor = .milliseconds(10)
        await run(quickFix)
        #expect(quickFix.last?.outcome == .notPasted(.selectionChanged))
        #expect(quickFix.last?.corrected == corrected)
        #expect(harness.quickFixPresenter.statuses == [.working, .failed])
        #expect(harness.quickFixPresenter.announcements.first?.contains("Your selection changed.") == true)
        #expect(try !#require(harness.actions.recorded.first).applied)
        // The mark stays until it is clicked.
        try await Task.sleep(for: .milliseconds(60))
        #expect(quickFix.status == .failed)
    }

    @Test func anotherAppInFrontIsNotPulledBack() async {
        let harness = harness()
        harness.system.frontmostApp = SourceApp(name: "Mail", bundleID: "com.apple.mail", processID: 7)
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(quickFix.last?.outcome == .notPasted(.movedAway))
        #expect(quickFix.status == .failed)
    }

    @Test func aProofreadThatChangedMostWordsWaitsForALook() async {
        let text = "the quick brown fox jumps over the lazy dog and then it runs far away into the woods"
        let answer = "Something else entirely was written here instead, which no proofread should ever do to a text."
        let harness = harness(selecting: text, answer: [answer])
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(quickFix.last?.outcome == .notPasted(.changedTooMuch))
    }

    @Test func aTerminalIsNeverPastedIntoWithoutASecondPress() async {
        let terminal = SourceApp(name: "Terminal", bundleID: "com.apple.Terminal", processID: 9)
        let harness = harness()
        harness.system.selection = SelectionCapture(app: terminal, text: original)
        harness.system.frontmostApp = terminal
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(quickFix.last?.outcome == .notPasted(.terminal))
    }

    @Test(arguments: [WritingError.overloaded, .truncated, .refused])
    func aFailedProofreadPastesNothing(error: WritingError) async {
        let harness = harness()
        harness.writing.script(deltas: ["hey can u"], error: error)
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(quickFix.last?.outcome == .failed(message: error.localizedDescription, error: error))
        #expect(quickFix.last?.corrected == nil)
        #expect(quickFix.status == .failed)
        #expect(harness.quickFixPresenter.announcements == ["Quick fix didn't work. \(error.localizedDescription)"])
        #expect(harness.actions.recorded.isEmpty)
    }

    @Test func anEmptyAnswerPastesNothing() async {
        let harness = harness(answer: ["  \n"])
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(quickFix.last?.outcome == .failed(
            message: WritingError.noOutput.localizedDescription, error: .noOutput
        ))
    }

    @Test(arguments: [false, true])
    func withoutTheKeyOrThePermissionNothingIsAsked(missingPermission: Bool) async {
        let harness = Harness(key: missingPermission ? "sk-test" : nil)
        harness.system.isAccessibilityGranted = !missingPermission
        harness.system.selection = SelectionCapture(app: Harness.slack, text: original)
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        #expect(harness.writing.requests.isEmpty)
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(harness.system.captureCount == (missingPermission ? 0 : 1))
        #expect(quickFix.last == nil)
        #expect(quickFix.status == .failed)
        // Nothing is kept, so a click opens the panel, whose setup says what is missing.
        #expect(quickFix.iconClicked() == nil)
        #expect(quickFix.status == .idle)
    }

    @Test func aSavedKeyThatCannotBeReadIsKeptAsAFailure() async throws {
        struct LockedKeys: APIKeyStore {
            func hasAPIKey() throws -> Bool { true }
            func loadAPIKey() throws -> String? { throw FakeFailure("locked") }
            func saveAPIKey(_ key: String) throws {}
            func deleteAPIKey() throws {}
        }
        let harness = harness()
        let services = AppServices(
            writing: harness.writing, styles: harness.styles, settings: harness.settings, apiKeys: LockedKeys(),
            system: harness.system
        )
        let panel = PanelViewModel(services: services, presenter: harness.presenter)
        let quickFix = QuickFixController(services: services, presenter: harness.quickFixPresenter)
        panel.quickFix = quickFix
        await run(quickFix)
        #expect(harness.writing.requests.isEmpty)
        #expect(quickFix.last?.outcome == .failed(
            message: WritingError.unreadableAPIKey.localizedDescription, error: .unreadableAPIKey
        ))
        panel.showLastQuickFix()
        #expect(panel.screen == .failed)
        #expect(panel.offersSettings)
    }

    // MARK: One at a time

    @Test func aSecondPressWhileOneWorksDoesNothing() async throws {
        let harness = harness()
        harness.writing.script(deltas: ["hey"], staysOpen: true)
        let quickFix = harness.makeQuickFix()
        quickFix.start()
        #expect(await eventually { harness.writing.requests.count == 1 })
        quickFix.start()
        try await Task.sleep(for: .milliseconds(30))
        #expect(harness.writing.requests.count == 1)
        #expect(harness.system.captureCount == 1)
        quickFix.interrupt()
    }

    @Test func aClickWhileItWorksHandsTheTextToThePanel() async throws {
        let harness = harness()
        harness.writing.script(deltas: ["hey"], staysOpen: true)
        let quickFix = harness.makeQuickFix()
        quickFix.start()
        #expect(await eventually { harness.writing.requests.count == 1 })

        #expect(quickFix.iconClicked() == .handOver(SelectionCapture(app: Harness.slack, text: original)))
        #expect(quickFix.status == .idle)
        try await Task.sleep(for: .milliseconds(30))
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(quickFix.last == nil)
        #expect(harness.quickFixPresenter.statuses == [.working, .idle])
    }

    @Test func openingThePanelStopsAQuickFixBeforeItPastes() async throws {
        let harness = harness()
        harness.writing.script(deltas: ["hey"], staysOpen: true)
        let panel = harness.makePanel()
        let quickFix = harness.makeQuickFix(panel: panel)
        quickFix.start()
        #expect(await eventually { harness.writing.requests.count == 1 })

        panel.begin(with: SelectionCapture(app: Harness.slack, text: "something else"))
        #expect(quickFix.status == .idle)
        try await Task.sleep(for: .milliseconds(30))
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(quickFix.last == nil)
    }

    // MARK: The icon's mark

    @Test func theCheckMarkGoesAfterAMoment() async {
        let harness = harness()
        let quickFix = harness.makeQuickFix()
        quickFix.timing.doneFor = .milliseconds(20)
        await run(quickFix)
        #expect(quickFix.status == .done)
        #expect(await eventually { quickFix.status == .idle })
        #expect(harness.quickFixPresenter.statuses == [.working, .done, .idle])
        // The quick fix is still there to show.
        #expect(quickFix.hasLast)
    }

    @Test func aClickOnTheMarkShowsTheLastQuickFix() async {
        let harness = harness()
        harness.system.replaceOutcome = .selectionChanged
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        #expect(quickFix.iconClicked() == .showLast)
        #expect(quickFix.status == .idle)
        // With the mark gone, a click is the panel's again.
        #expect(quickFix.iconClicked() == nil)
    }

    @Test func openingThePanelTakesTheMarkAway() async {
        let harness = harness()
        harness.system.replaceOutcome = .selectionChanged
        let panel = harness.makePanel()
        let quickFix = harness.makeQuickFix(panel: panel)
        await run(quickFix)
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))
        #expect(quickFix.status == .idle)
        #expect(quickFix.hasLast)
    }

    @Test func aNewQuickFixStartsOverAMark() async {
        let harness = harness()
        harness.system.replaceOutcome = .selectionChanged
        let quickFix = harness.makeQuickFix()
        await run(quickFix)
        harness.system.replaceOutcome = .inserted
        await run(quickFix)
        #expect(harness.quickFixPresenter.statuses == [.working, .failed, .working, .done])
        #expect(quickFix.last?.outcome == .applied)
    }

    // MARK: In the panel afterwards

    @Test func aQuickFixThatWentInIsShownForReading() async throws {
        let harness = harness()
        let panel = harness.makePanel()
        let quickFix = harness.makeQuickFix(panel: panel)
        await run(quickFix)

        panel.showLastQuickFix()
        #expect(panel.screen == .result)
        #expect(panel.draft == corrected)
        // The app holds the corrected text now.
        #expect(panel.capture == SelectionCapture(app: Harness.slack, text: corrected))
        #expect(panel.originalText == original)
        #expect(panel.proofreadChanges?.count == 1)
        #expect(panel.offersChanges)
        #expect(panel.showsQuickFixInPlace)
        #expect(!panel.canApplyResult)
        #expect(panel.dictationField == nil)
        let notice = try #require(panel.notice)
        #expect(notice.hasPrefix("Quick fix put this in Slack at "))
        #expect(notice.hasSuffix("Press ⌘Z in Slack to bring back what you wrote."))

        // Nothing is asked again, and nothing is pasted from here.
        panel.tryAgain()
        panel.adjustment = "shorter"
        panel.applyAdjustment()
        panel.applyResult()
        #expect(harness.writing.requests.count == 1)
        #expect(harness.system.replaceCalls.count == 1)
        panel.copyResult()
        #expect(harness.system.copied == [corrected])
    }

    @Test func aQuickFixWithNothingToCorrectIsShownForReading() async {
        let harness = harness(answer: ["hey can u send it to me tmrw"])
        let panel = harness.makePanel()
        let quickFix = harness.makeQuickFix(panel: panel)
        await run(quickFix)
        panel.showLastQuickFix()
        #expect(panel.screen == .result)
        #expect(panel.proofreadChanges?.count == 0)
        #expect(panel.showsQuickFixInPlace)
        #expect(panel.notice?.hasSuffix("so Slack was left as it was.") == true)
    }

    @Test func aQuickFixThatWasNotPastedCanBePutInFromThePanel() async throws {
        let harness = harness()
        harness.system.replaceOutcome = .selectionChanged
        let panel = harness.makePanel()
        let quickFix = harness.makeQuickFix(panel: panel)
        await run(quickFix)

        harness.system.replaceOutcome = .inserted
        panel.showLastQuickFix()
        #expect(panel.screen == .result)
        #expect(panel.capture == SelectionCapture(app: Harness.slack, text: original))
        #expect(!panel.showsQuickFixInPlace)
        #expect(panel.canApplyResult)
        #expect(panel.primaryActionTitle == "Replace")
        #expect(panel.notice == QuickFixProblem.selectionChanged.panelNotice(app: "Slack"))

        panel.applyResult()
        await panel.runningTask?.value
        let call = try #require(harness.system.replaceCalls.last)
        #expect(harness.system.replaceCalls.count == 2)
        #expect(call.expected == original)
        #expect(call.text == corrected)
        // Put in from the panel, it counts as a fix put back.
        #expect(try #require(harness.actions.recorded.first).applied)
    }

    @Test func aFailedQuickFixShowsItsErrorAndCanBeTriedAgain() async throws {
        let harness = harness()
        harness.writing.script(deltas: [], error: WritingError.overloaded)
        let panel = harness.makePanel()
        let quickFix = harness.makeQuickFix(panel: panel)
        await run(quickFix)

        harness.writing.script(deltas: [corrected])
        panel.showLastQuickFix()
        #expect(panel.screen == .failed)
        #expect(panel.errorMessage == WritingError.overloaded.localizedDescription)
        #expect(!panel.offersSettings)

        panel.retryFailed()
        await panel.runningTask?.value
        #expect(panel.screen == .result)
        #expect(panel.draft == corrected)
        #expect(harness.writing.requests.count == 2)
        #expect(harness.writing.requests.last?.task == .proofread(text: original))
    }

    @Test func withoutAQuickFixThePanelStaysAsItIs() {
        let harness = Harness()
        let panel = harness.makePanel()
        _ = harness.makeQuickFix(panel: panel)
        panel.begin(with: SelectionCapture(app: Harness.slack, text: original))
        panel.showLastQuickFix()
        #expect(panel.screen == .home)
        #expect(panel.lastRequest == nil)
    }

    @Test func goingBackFromAQuickFixLeavesItBehind() async {
        let harness = harness()
        let panel = harness.makePanel()
        let quickFix = harness.makeQuickFix(panel: panel)
        await run(quickFix)
        panel.showLastQuickFix()
        panel.goBack()
        #expect(panel.screen == .home)
        #expect(!panel.showsQuickFixInPlace)
        #expect(panel.dictationField == .instruction)
    }
}
