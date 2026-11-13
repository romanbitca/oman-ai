import Foundation
import OmanCore
import Testing
@testable import OmanUI

/// The person's own actions: made in Settings, run from the panel or from a shortcut.
@MainActor
@Suite struct CustomActionsTests {
    private let selection = SelectionCapture(app: Harness.slack, text: "rough text")
    private let combo = KeyCombo(keyCode: 1, modifiers: KeyCombo.control | KeyCombo.option)
    private let shorter = CustomAction(name: "Make it shorter", instruction: "  Cut it to half its length  ")
    private let summary = CustomAction(name: "Summary", instruction: "Sum this up in one line", output: .read)

    private func preparedHarness(actions: [CustomAction] = [], styles: [WritingStyle] = []) -> Harness {
        let harness = Harness()
        harness.customActions.seed(actions)
        harness.styles.seed(styles)
        return harness
    }

    private func setPreferences(_ harness: Harness, _ change: (inout AppPreferences) -> Void) throws {
        var preferences = try harness.settings.preferences()
        change(&preferences)
        try harness.settings.setPreferences(preferences)
    }

    // MARK: In the panel

    @Test func thePanelOffersOnlyActionsWithAnInstruction() {
        let blank = CustomAction(name: "Half made", instruction: "  \n ")
        let harness = preparedHarness(actions: [shorter, blank, summary])
        let panel = harness.makePanel()
        panel.begin(with: selection)
        #expect(panel.customActions == [shorter, summary])
    }

    @Test func anActionToPasteIsSentAsTypingItsInstructionWouldBe() async throws {
        let style = WritingStyle(name: "Slack", samples: [StyleSample(text: "hey, quick one")])
        let harness = preparedHarness(actions: [shorter], styles: [style])
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.selectStyle(style)
        panel.setIncludesMessages(true)
        panel.contextText = "the thread so far"

        panel.runCustomAction(shorter)
        #expect(await eventually { panel.screen == .result })
        let sent = try #require(harness.writing.requests.first)
        #expect(sent.task == .custom(text: "rough text", instruction: "Cut it to half its length", output: .paste))
        #expect(sent.style == style)
        #expect(sent.context.pastedText == "the thread so far")

        // The same instruction typed into Describe your change carries everything else the same way.
        panel.goBack()
        panel.instruction = "Cut it to half its length"
        panel.rewrite()
        #expect(await eventually { harness.writing.requests.count == 2 && panel.screen == .result })
        var typed = try #require(harness.writing.requests.last)
        #expect(typed.task == .rewrite(text: "rough text", instruction: "Cut it to half its length"))
        typed.task = sent.task
        #expect(typed == sent)
    }

    @Test func theResultOfAnActionToPasteReplacesTheSelection() async {
        let harness = preparedHarness(actions: [shorter])
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.runCustomAction(shorter)
        #expect(await eventually { panel.screen == .result })
        #expect(!panel.isOnlyToRead)
        #expect(panel.canApplyResult)
        #expect(panel.primaryActionTitle == "Replace")
        #expect(panel.dictationField == .adjustment)
        #expect(panel.originalText == "rough text")

        panel.applyResult()
        #expect(await eventually { harness.system.replaceCalls.count == 1 })
        #expect(harness.system.replaceCalls.first?.text == "Hello world")
    }

    @Test func onDictatedWordsAnActionsResultGoesInWithInsert() async {
        let harness = preparedHarness(actions: [shorter])
        let panel = harness.makePanel()
        panel.begin(withDictatedText: "so basically i wanted to say we should move the deadline", from: Harness.slack)
        #expect(panel.customActions == [shorter])
        panel.runCustomAction(shorter)
        #expect(await eventually { panel.screen == .result })
        #expect(panel.primaryActionTitle == "Insert")
        panel.applyResult()
        #expect(await eventually { harness.system.insertCalls.count == 1 })
        #expect(harness.system.replaceCalls.isEmpty)
    }

    @Test func aChangeAskedForAfterAnActionToPasteRevisesItsResult() async throws {
        let harness = preparedHarness(actions: [shorter])
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.runCustomAction(shorter)
        #expect(await eventually { panel.screen == .result })
        panel.adjustment = "warmer"
        panel.applyAdjustment()
        #expect(await eventually { harness.writing.requests.count == 2 })
        let revised = try #require(harness.writing.requests.last)
        #expect(revised.task == .custom(text: "rough text", instruction: "Cut it to half its length", output: .paste))
        #expect(revised.refinement == Refinement(currentDraft: "Hello world", adjustment: "warmer"))
    }

    @Test func anActionToReadTakesTheContextButNoTemplate() async throws {
        let style = WritingStyle(name: "Slack", samples: [StyleSample(text: "hey, quick one")])
        let harness = preparedHarness(actions: [summary], styles: [style])
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.selectStyle(style)
        panel.setIncludesMessages(true)
        panel.contextText = "the thread so far"

        panel.runCustomAction(summary)
        #expect(await eventually { panel.screen == .result })
        let sent = try #require(harness.writing.requests.first)
        #expect(sent.task == .custom(text: "rough text", instruction: "Sum this up in one line", output: .read))
        #expect(sent.style == nil)
        #expect(sent.context.pastedText == "the thread so far")
    }

    @Test func theAnswerOfAnActionToReadIsNeverPasted() async throws {
        let harness = preparedHarness(actions: [summary])
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.runCustomAction(summary)
        #expect(await eventually { panel.screen == .result })
        #expect(panel.isOnlyToRead)
        #expect(!panel.canApplyResult)
        #expect(panel.dictationField == nil)

        panel.applyResult()
        let accept = try #require(AppPreferences().combo(for: .acceptResult))
        #expect(!panel.handlePanelShortcut(accept))
        panel.adjustment = "shorter"
        panel.applyAdjustment()
        await Task.yield()
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(harness.system.insertCalls.isEmpty)
        #expect(harness.writing.requests.count == 1)
    }

    @Test func tryAgainAsksAnActionToReadAfresh() async throws {
        let harness = preparedHarness(actions: [summary])
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.runCustomAction(summary)
        #expect(await eventually { panel.screen == .result })
        panel.tryAgain()
        #expect(await eventually { harness.writing.requests.count == 2 && panel.screen == .result })
        #expect(harness.writing.requests[1] == harness.writing.requests[0])
    }

    @Test func anActionNeedsASelection() {
        let harness = preparedHarness(actions: [shorter])
        let panel = harness.makePanel()
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))
        panel.runCustomAction(shorter)
        #expect(panel.screen == .compose)
        #expect(harness.writing.requests.isEmpty)
    }

    @Test func whatAnActionWroteCountsAsYourActionsAndAsAFixOncePutBack() async throws {
        let harness = preparedHarness(actions: [shorter])
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.runCustomAction(shorter)
        #expect(await eventually { panel.screen == .result })
        let noted = try #require(harness.actions.recorded.first)
        #expect(noted.kind == .custom)
        #expect(noted.appName == "Slack")
        #expect(noted.changes == nil)

        panel.applyResult()
        #expect(await eventually { harness.actions.recorded.first?.applied == true })
    }

    // MARK: Shortcuts

    @Test func anActionsShortcutKeyRoundTripsAndIsGlobal() {
        let action = ShortcutAction.custom(shorter.id)
        #expect(action.storageKey == "custom:\(shorter.id.uuidString)")
        #expect(ShortcutAction(storageKey: action.storageKey) == action)
        #expect(ShortcutAction(storageKey: "custom:not-an-id") == nil)
        #expect(action.isGlobal)
        #expect(!action.isDictation)

        var preferences = AppPreferences()
        preferences.setCombo(combo, for: action)
        #expect(preferences.globalShortcuts == [action: combo])
        let saved = try? JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(saved?.combo(for: action) == combo)
    }

    @Test func anActionsShortcutRunsItOnTheSelection() async {
        let harness = preparedHarness(actions: [summary, shorter])
        let panel = harness.makePanel()
        // What the menu bar does for a global shortcut: read the selection, then run the action straight after.
        panel.begin(with: selection)
        panel.run(.custom(shorter.id))
        #expect(await eventually { panel.screen == .result })
        #expect(harness.writing.requests.map(\.task) == [
            .custom(text: "rough text", instruction: "Cut it to half its length", output: .paste),
        ])
    }

    @Test func anActionsShortcutWaitsForTheScreenWhenThatIsTheDefault() async throws {
        let harness = preparedHarness(actions: [summary])
        try setPreferences(harness) { $0.includesScreenByDefault = true }
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.run(.custom(summary.id))
        #expect(panel.screen == .working)
        #expect(await eventually { panel.screen == .result })
        #expect(harness.writing.requests.first?.context.screenshot != nil)
    }

    @Test func anActionsShortcutWithNothingSelectedOrNoActionDoesNothing() {
        let harness = preparedHarness(actions: [shorter])
        let panel = harness.makePanel()
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))
        panel.run(.custom(shorter.id))
        #expect(panel.screen == .compose)

        panel.begin(with: selection)
        panel.run(.custom(UUID()))
        #expect(panel.screen == .home)
        #expect(harness.writing.requests.isEmpty)
    }

    @Test func aShortcutForAnActionWithoutAnInstructionDoesNothing() {
        let blank = CustomAction(name: "Half made")
        let harness = preparedHarness(actions: [blank])
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.run(.custom(blank.id))
        #expect(panel.screen == .home)
        #expect(harness.writing.requests.isEmpty)
    }

    // MARK: In Settings

    @Test func settingsListsTheActionsAndGivesEachAShortcutRow() {
        let harness = preparedHarness(actions: [shorter, summary], styles: [WritingStyle(name: "Slack")])
        let settings = harness.makeSettings()
        settings.reload()
        #expect(settings.customActions == [shorter, summary])
        #expect(settings.globalShortcutActions.suffix(2) == [.custom(shorter.id), .custom(summary.id)])
        #expect(settings.globalShortcutActions.count == ShortcutAction.globalActions.count + 3)
        #expect(settings.title(for: .custom(shorter.id)) == "Make it shorter")
        #expect(settings.title(for: .custom(UUID())) == "Your action")
    }

    @Test func aNewActionIsSavedAndEveryChangeWithIt() throws {
        let harness = preparedHarness()
        let settings = harness.makeSettings()
        settings.reload()
        let id = settings.createCustomAction()
        #expect(harness.customActions.actions == [CustomAction(id: id, name: "New action")])

        settings.updateCustomAction(id: id) { $0.name = "Bullets" }
        settings.updateCustomAction(id: id) { $0.instruction = "Turn this into bullet points" }
        settings.updateCustomAction(id: id) { $0.output = .read }
        let expected = CustomAction(id: id, name: "Bullets", instruction: "Turn this into bullet points", output: .read)
        #expect(settings.customActions == [expected])
        #expect(harness.customActions.actions == [expected])
    }

    @Test func recordingAShortcutForAnActionRegistersIt() {
        let harness = preparedHarness(actions: [shorter])
        let settings = harness.makeSettings()
        settings.reload()
        settings.startRecording(.custom(shorter.id))
        #expect(harness.system.suspendCount == 1)
        settings.finishRecording(with: combo)
        #expect(settings.preferences.combo(for: .custom(shorter.id)) == combo)
        #expect(harness.system.registered == [.custom(shorter.id): combo])
    }

    @Test func aComboMovesFromAnActionByName() throws {
        let harness = preparedHarness(actions: [shorter])
        try setPreferences(harness) { $0.setCombo(combo, for: .custom(shorter.id)) }
        let settings = harness.makeSettings()
        settings.reload()
        settings.startRecording(.proofread)
        settings.finishRecording(with: combo)
        #expect(settings.preferences.combo(for: .custom(shorter.id)) == nil)
        #expect(settings.shortcutNotice == "\(combo.displayString) moved here from Make it shorter.")
    }

    @Test func deletingAnActionTakesItsShortcutWithIt() throws {
        let harness = preparedHarness(actions: [shorter, summary])
        let other = KeyCombo(keyCode: 2, modifiers: KeyCombo.control | KeyCombo.option)
        try setPreferences(harness) {
            $0.setCombo(combo, for: .custom(shorter.id))
            $0.setCombo(other, for: .custom(summary.id))
        }
        let settings = harness.makeSettings()
        settings.reload()
        settings.deleteCustomAction(id: shorter.id)

        #expect(settings.customActions == [summary])
        #expect(harness.customActions.actions == [summary])
        #expect(settings.preferences.combo(for: .custom(shorter.id)) == nil)
        #expect(try harness.settings.preferences().combo(for: .custom(shorter.id)) == nil)
        #expect(harness.system.registered == [.custom(summary.id): other])
    }

    @Test func deletingTheActionWhoseShortcutIsBeingRecordedStopsRecording() {
        let harness = preparedHarness(actions: [shorter])
        let settings = harness.makeSettings()
        settings.reload()
        settings.startRecording(.custom(shorter.id))
        settings.deleteCustomAction(id: shorter.id)
        #expect(settings.recordingAction == nil)
    }

    @Test func aStoreThatFailsSaysSoAndKeepsWhatWasThere() {
        let harness = preparedHarness(actions: [shorter])
        let settings = harness.makeSettings()
        settings.reload()
        harness.customActions.fail(with: FakeFailure("The disk is full."))
        settings.deleteCustomAction(id: shorter.id)
        #expect(settings.customActionError == "The disk is full.")
        #expect(settings.customActions == [shorter])

        settings.reload()
        #expect(settings.customActions.isEmpty)
        #expect(settings.customActionError == "The disk is full.")
    }

    // MARK: Counted

    @Test func spendingSaysHowManyOfYourActionsWerePutBack() {
        let count = SpendingSummary.KindCount(kind: .custom, written: 3, fixes: 2, cost: 0.01)
        #expect(WritingTask.Kind.custom.displayName == "Your actions")
        #expect(SpendingSettingsView.detail(of: count) == "3 written · 2 put back")
    }

    @Test func theWindowCountsAnActionPutBackAsARewrite() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Chisinau"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15)))
        let earlier = now.addingTimeInterval(-3_600)
        let actions = [
            WritingAction(date: earlier, kind: .custom, model: "x", appName: "Slack", applied: true),
            WritingAction(date: earlier, kind: .custom, model: "x", appName: "Slack", applied: false),
            WritingAction(date: earlier, kind: .rewrite, model: "x", appName: "Slack", applied: true),
        ]
        let summary = HomeSummary.make(counts: [], actions: actions, period: .week, now: now, calendar: calendar)
        #expect(summary.fixes == HomeSummary.Fixes(proofread: 0, rewritten: 2, composed: 0))
    }
}
