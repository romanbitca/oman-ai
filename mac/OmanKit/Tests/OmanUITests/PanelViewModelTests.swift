import Foundation
import OmanCore
import Testing
@testable import OmanUI

@MainActor
@Suite struct PanelViewModelTests {
    private let selection = SelectionCapture(app: Harness.slack, text: "hey can u send it")
    private let noSelection = SelectionCapture(app: Harness.slack, text: nil)

    private func style(_ name: String = "Slack") -> WritingStyle {
        WritingStyle(name: name, samples: [StyleSample(text: "yo")])
    }

    private func finish(_ model: PanelViewModel) async {
        await model.runningTask?.value
    }

    // MARK: Routing

    @Test func missingKeyRoutesToSetup() {
        let harness = Harness(key: nil)
        let model = harness.makePanel()
        model.begin(with: selection)
        #expect(model.screen == .setup)
        #expect(model.hasAPIKey == false)
        model.panelDidClose()
    }

    @Test func missingAccessibilityRoutesToSetup() {
        let harness = Harness()
        harness.system.isAccessibilityGranted = false
        let model = harness.makePanel()
        model.begin(with: selection)
        #expect(model.screen == .setup)
        model.panelDidClose()
    }

    @Test func selectionRoutesHomeAndNoSelectionRoutesToCompose() {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        #expect(model.screen == .home)
        model.begin(with: noSelection)
        #expect(model.screen == .compose)
        #expect(model.canGoBackFromCompose == false)
    }

    @Test func savingKeyAndGrantingAccessibilityLeavesSetup() async {
        let harness = Harness(key: nil)
        harness.system.isAccessibilityGranted = false
        let model = harness.makePanel()
        model.begin(with: noSelection)

        model.apiKeyDraft = "  sk-new  "
        await model.saveSetupKey()
        #expect(harness.writing.validations == ["sk-new"])
        #expect(harness.keys.current == "sk-new")
        #expect(model.screen == .setup)

        model.allowAccessibility()
        #expect(harness.system.accessibilityRequests == 1)
        #expect(model.isPinned)

        harness.system.isAccessibilityGranted = true
        model.refreshSetup()
        #expect(model.screen == .compose)
        #expect(model.isPinned == false)
        #expect(harness.presenter.pinnedValues.last == false)
    }

    @Test func invalidSetupKeyIsNotSavedAndShowsError() async {
        let harness = Harness(key: nil)
        harness.writing.scriptValidation(error: WritingError.invalidAPIKey)
        let model = harness.makePanel()
        model.begin(with: selection)
        model.apiKeyDraft = "bad"
        await model.saveSetupKey()
        #expect(harness.keys.current == nil)
        #expect(model.setupError == WritingError.invalidAPIKey.localizedDescription)
        #expect(model.screen == .setup)
        model.panelDidClose()
    }

    @Test func beginResetsStateAndPreselectsLastStyle() async throws {
        let harness = Harness()
        let saved = style()
        harness.styles.seed([saved])
        try harness.styles.setLastStyleID(saved.id, forBundleID: "com.tinyspeck.slackmacgap")
        let model = harness.makePanel()
        model.begin(with: selection)
        #expect(model.selectedStyleID == saved.id)

        model.instruction = "shorter"
        model.composePrompt = "draft"
        model.contextText = "context"
        model.isContextExpanded = true
        model.togglePin()
        #expect(model.isPinned)
        model.proofread()
        await finish(model)
        #expect(model.draft == "Hello world")

        model.begin(with: selection)
        #expect(model.instruction.isEmpty)
        #expect(model.composePrompt.isEmpty)
        #expect(model.contextText.isEmpty)
        #expect(model.isContextExpanded == false)
        #expect(model.draft.isEmpty)
        #expect(model.isPinned == false)
        #expect(harness.presenter.pinnedValues.last == false)
        #expect(model.screen == .home)
    }

    @Test func preselectionIgnoresDeletedStyleAndOtherApps() throws {
        let harness = Harness()
        try harness.styles.setLastStyleID(UUID(), forBundleID: "com.tinyspeck.slackmacgap")
        harness.styles.seed([style()])
        let model = harness.makePanel()
        model.begin(with: selection)
        #expect(model.selectedStyleID == nil)
    }

    // MARK: Requests

    @Test func proofreadSendsNoStyleOrContext() async throws {
        let harness = Harness()
        let saved = style()
        harness.styles.seed([saved])
        try harness.styles.setLastStyleID(saved.id, forBundleID: "com.tinyspeck.slackmacgap")
        let model = harness.makePanel()
        model.begin(with: selection)
        model.contextText = "client said hi"
        model.proofread()
        await finish(model)

        let request = try #require(harness.writing.requests.last)
        #expect(request.task == .proofread(text: "hey can u send it"))
        #expect(request.style == nil)
        #expect(request.context == WritingContext())
        #expect(request.refinement == nil)
        #expect(harness.writing.keys == ["sk-test"])
    }

    @Test func rewriteCarriesInstructionStyleContextAndModel() async throws {
        let harness = Harness()
        try harness.settings.setSelectedModel(.opus)
        let saved = style()
        harness.styles.seed([saved])
        try harness.styles.setLastStyleID(saved.id, forBundleID: "com.tinyspeck.slackmacgap")
        let model = harness.makePanel()
        model.begin(with: selection)
        model.instruction = "  shorter  "
        model.contextText = "client said hi"
        model.rewrite()
        await finish(model)

        let request = try #require(harness.writing.requests.last)
        #expect(request.task == .rewrite(text: "hey can u send it", instruction: "shorter"))
        #expect(request.style == saved)
        #expect(request.context.pastedText == "client said hi")
        #expect(request.model == .opus)
        #expect(model.screen == .result)
    }

    @Test func blankInstructionBecomesNil() async throws {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.instruction = "   "
        model.rewrite()
        await finish(model)
        let request = try #require(harness.writing.requests.last)
        #expect(request.task == .rewrite(text: "hey can u send it", instruction: nil))
    }

    @Test func chipClickRunsRewriteAndRecordsLastStyle() async throws {
        let harness = Harness()
        let saved = style()
        harness.styles.seed([saved])
        let model = harness.makePanel()
        model.begin(with: selection)
        model.chooseStyleAndRewrite(saved)
        await finish(model)

        #expect(model.selectedStyleID == saved.id)
        #expect(try harness.styles.lastStyleID(forBundleID: "com.tinyspeck.slackmacgap") == saved.id)
        let request = try #require(harness.writing.requests.last)
        #expect(request.style == saved)
        #expect(request.task == .rewrite(text: "hey can u send it", instruction: nil))
    }

    @Test func composeWithoutSelection() async throws {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: noSelection)
        #expect(model.canCompose == false)
        model.composePrompt = " say thanks "
        #expect(model.canCompose)
        model.compose()
        await finish(model)

        let request = try #require(harness.writing.requests.last)
        #expect(request.task == .compose(request: "say thanks", selectedText: nil))
        #expect(model.primaryActionTitle == "Insert")
        #expect(model.originalText == nil)
    }

    @Test func composeWithSelectionSendsItAsReference() async throws {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.openCompose()
        #expect(model.screen == .compose)
        #expect(model.canGoBackFromCompose)
        model.composePrompt = "reply politely"
        model.compose()
        await finish(model)

        let request = try #require(harness.writing.requests.last)
        #expect(request.task == .compose(request: "reply politely", selectedText: "hey can u send it"))
    }

    @Test func emptyComposeDoesNothing() {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: noSelection)
        model.composePrompt = "   "
        model.compose()
        #expect(harness.writing.requests.isEmpty)
        #expect(model.screen == .compose)
    }

    @Test func composeChipsOnlyToggleSelection() {
        let harness = Harness()
        let saved = style()
        harness.styles.seed([saved])
        let model = harness.makePanel()
        model.begin(with: noSelection)
        model.toggleComposeStyle(saved)
        #expect(model.selectedStyleID == saved.id)
        model.toggleComposeStyle(saved)
        #expect(model.selectedStyleID == nil)
        #expect(harness.writing.requests.isEmpty)
        #expect(model.screen == .compose)
    }

    @Test func tryAgainAndAdjustSendRefinements() async throws {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.rewrite()
        await finish(model)
        let first = try #require(harness.writing.requests.last)

        model.tryAgain()
        await finish(model)
        let second = try #require(harness.writing.requests.last)
        #expect(second.task == first.task)
        #expect(second.refinement == Refinement(
            currentDraft: "Hello world",
            adjustment: "Write a different version of this."
        ))

        harness.writing.script(deltas: ["Shorter"])
        model.adjustment = " shorter "
        model.applyAdjustment()
        #expect(model.adjustment.isEmpty)
        await finish(model)
        let third = try #require(harness.writing.requests.last)
        #expect(third.refinement == Refinement(currentDraft: "Hello world", adjustment: "shorter"))
        #expect(model.draft == "Shorter")
    }

    @Test func blankAdjustmentDoesNothing() async {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.rewrite()
        await finish(model)
        let count = harness.writing.requests.count
        model.adjustment = "  "
        model.applyAdjustment()
        #expect(harness.writing.requests.count == count)
        #expect(model.screen == .result)
    }

    // MARK: Streaming and failures

    @Test func deltasAccumulateWhileWorking() async {
        let harness = Harness()
        harness.writing.script(deltas: ["One", " two"], staysOpen: true)
        let model = harness.makePanel()
        model.begin(with: selection)
        model.rewrite()
        #expect(model.screen == .working)
        #expect(await eventually { model.draft == "One two" })
        #expect(model.screen == .working)
        model.panelDidClose()
    }

    @Test func stopReturnsToPreviousScreenWithoutFailing() async {
        let harness = Harness()
        harness.writing.script(deltas: ["partial"], staysOpen: true)
        let model = harness.makePanel()
        model.begin(with: selection)
        model.rewrite()
        #expect(await eventually { model.draft == "partial" })
        model.stop()
        #expect(model.screen == .home)
        #expect(model.draft.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func stopDuringAdjustmentRestoresTheDraft() async {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.rewrite()
        await finish(model)

        harness.writing.script(deltas: ["partial"], staysOpen: true)
        model.adjustment = "shorter"
        model.applyAdjustment()
        #expect(await eventually { model.draft == "partial" })
        model.stop()
        #expect(model.screen == .result)
        #expect(model.draft == "Hello world")
    }

    @Test func errorDiscardsPartialDraft() async {
        let harness = Harness()
        harness.writing.script(deltas: ["partial"], error: WritingError.refused)
        let model = harness.makePanel()
        model.begin(with: selection)
        model.rewrite()
        await finish(model)
        #expect(model.screen == .failed)
        #expect(model.draft.isEmpty)
        #expect(model.errorMessage == WritingError.refused.localizedDescription)
        #expect(model.offersSettings == false)
    }

    @Test func failedTryAgainResendsExactRequest() async throws {
        let harness = Harness()
        harness.writing.script(deltas: [], error: WritingError.overloaded)
        let model = harness.makePanel()
        model.begin(with: selection)
        model.instruction = "shorter"
        model.rewrite()
        await finish(model)
        let failed = try #require(harness.writing.requests.last)

        harness.writing.script(deltas: ["Fixed"])
        model.retryFailed()
        await finish(model)
        #expect(harness.writing.requests.count == 2)
        #expect(harness.writing.requests.last == failed)
        #expect(model.screen == .result)
    }

    @Test func failedBackReturnsToBaseScreen() async {
        let harness = Harness()
        harness.writing.script(deltas: [], error: WritingError.overloaded)
        let model = harness.makePanel()
        model.begin(with: selection)
        model.openCompose()
        model.composePrompt = "draft"
        model.compose()
        await finish(model)
        model.goBack()
        #expect(model.screen == .compose)
        #expect(model.errorMessage == nil)
    }

    @Test func invalidKeyOffersSettings() async {
        let harness = Harness()
        harness.writing.script(deltas: [], error: WritingError.invalidAPIKey)
        let model = harness.makePanel()
        model.begin(with: selection)
        model.rewrite()
        await finish(model)
        #expect(model.offersSettings)
        model.openSettings()
        #expect(harness.presenter.settingsCount == 1)
    }

    @Test func keyRemovedAfterBeginFailsWithMissingKey() throws {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        try harness.keys.deleteAPIKey()
        model.rewrite()
        #expect(model.screen == .failed)
        #expect(model.errorMessage == WritingError.missingAPIKey.localizedDescription)
        #expect(model.offersSettings)
        #expect(harness.writing.requests.isEmpty)
    }

    @Test func closingThePanelCancelsTheRun() async {
        let harness = Harness()
        harness.writing.script(deltas: ["partial"], staysOpen: true)
        let model = harness.makePanel()
        model.begin(with: selection)
        model.rewrite()
        let task = model.runningTask
        model.panelDidClose()
        #expect(model.runningTask == nil)
        await task?.value
        #expect(model.screen == .working)
    }

    // MARK: Applying the result

    private func readyResult(_ harness: Harness, capture: SelectionCapture? = nil) async -> PanelViewModel {
        let model = harness.makePanel()
        model.begin(with: capture ?? selection)
        model.rewrite()
        await finish(model)
        return model
    }

    @Test func replaceInsertedStaysHidden() async throws {
        let harness = Harness()
        let model = await readyResult(harness)
        #expect(model.primaryActionTitle == "Replace")
        model.applyResult()
        await finish(model)

        let call = try #require(harness.system.replaceCalls.last)
        #expect(call.expected == "hey can u send it")
        #expect(call.text == "Hello world")
        #expect(call.app == Harness.slack)
        #expect(harness.presenter.hideCount == 1)
        #expect(harness.presenter.showCount == 0)
        #expect(model.runningTask == nil)
    }

    @Test func replaceSelectionChangedShowsPanelAndNotice() async {
        let harness = Harness()
        harness.system.replaceOutcome = .selectionChanged
        let model = await readyResult(harness)
        model.applyResult()
        await finish(model)
        #expect(harness.presenter.hideCount == 1)
        #expect(harness.presenter.showCount == 1)
        #expect(model.notice == "Your selection changed. Select the text again and press Replace, or use Copy.")
        #expect(model.screen == .result)
    }

    @Test func replaceSourceUnavailableNamesTheApp() async {
        let harness = Harness()
        harness.system.replaceOutcome = .sourceUnavailable
        let model = await readyResult(harness)
        model.applyResult()
        await finish(model)
        #expect(harness.presenter.showCount == 1)
        #expect(model.notice == "Slack is no longer available. Use Copy instead.")
    }

    @Test func replacePermissionMissingExplains() async {
        let harness = Harness()
        harness.system.replaceOutcome = .permissionMissing
        let model = await readyResult(harness)
        model.applyResult()
        await finish(model)
        #expect(harness.presenter.showCount == 1)
        #expect(model.notice == "OmanAI needs Accessibility permission to paste.")
    }

    @Test func composeInsertsAtCursor() async throws {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: noSelection)
        model.composePrompt = "say thanks"
        model.compose()
        await finish(model)
        model.applyResult()
        await finish(model)

        #expect(harness.system.replaceCalls.isEmpty)
        let call = try #require(harness.system.insertCalls.last)
        #expect(call.text == "Hello world")
        #expect(call.app == Harness.slack)
        #expect(harness.presenter.hideCount == 1)
    }

    @Test func composeWithoutAppCannotInsert() async {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: SelectionCapture(app: nil, text: nil))
        model.composePrompt = "say thanks"
        model.compose()
        await finish(model)
        #expect(model.canApplyResult == false)
        model.applyResult()
        #expect(harness.system.insertCalls.isEmpty)
        #expect(harness.presenter.hideCount == 0)
    }

    @Test func copyPutsDraftOnClipboardAndShowsNotice() async {
        let harness = Harness()
        let model = await readyResult(harness)
        model.copyResult()
        #expect(harness.system.copied == ["Hello world"])
        #expect(model.notice == "Copied")
    }

    @Test func showOriginalUsesSourceText() async {
        let harness = Harness()
        let model = await readyResult(harness)
        #expect(model.originalText == "hey can u send it")
    }

    // MARK: Context

    @Test func useClipboardAppendsAndExpands() {
        let harness = Harness()
        harness.system.clipboard = "from clipboard"
        let model = harness.makePanel()
        model.begin(with: selection)
        #expect(model.clipboardCandidate == "from clipboard")
        model.contextText = "typed"
        model.useClipboard()
        #expect(model.contextText == "typed\n\nfrom clipboard")
        #expect(model.isContextExpanded)
        #expect(model.clipboardCandidate == nil)
    }

    @Test func noClipboardMeansNoCandidate() {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        #expect(model.clipboardCandidate == nil)
    }

    @Test func includeScreenWhenGrantedAttachesScreenshot() async throws {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.setIncludeScreen(true)
        #expect(model.includeScreen)
        await model.screenTask?.value
        #expect(model.screenshot != nil)

        model.rewrite()
        await finish(model)
        let request = try #require(harness.writing.requests.last)
        #expect(request.context.screenshot == model.screenshot)

        model.setIncludeScreen(false)
        #expect(model.includeScreen == false)
        #expect(model.screenshot == nil)
    }

    @Test func includeScreenWhenNotGrantedRequestsAndStaysOff() {
        let harness = Harness()
        harness.system.isScreenCaptureGranted = false
        let model = harness.makePanel()
        model.begin(with: selection)
        model.setIncludeScreen(true)
        #expect(harness.system.screenRequests == 1)
        #expect(model.includeScreen == false)
        #expect(model.screenshot == nil)
        #expect(model.screenHint != nil)
    }

    @Test func includeScreenFailureShowsErrorInline() async {
        let harness = Harness()
        harness.system.screenshotResult = .failure(FakeFailure("No window"))
        let model = harness.makePanel()
        model.begin(with: selection)
        model.setIncludeScreen(true)
        await model.screenTask?.value
        #expect(model.includeScreen == false)
        #expect(model.screenHint == "No window")
    }

    @Test func includeScreenIsOffAfterBegin() async {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.setIncludeScreen(true)
        await model.screenTask?.value
        model.begin(with: selection)
        #expect(model.includeScreen == false)
        #expect(model.screenshot == nil)
    }

    // MARK: Presenter

    @Test func pinTogglesPresenter() {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.togglePin()
        #expect(model.isPinned)
        #expect(harness.presenter.pinnedValues.last == true)
        model.togglePin()
        #expect(model.isPinned == false)
        #expect(harness.presenter.pinnedValues.last == false)
    }
}
