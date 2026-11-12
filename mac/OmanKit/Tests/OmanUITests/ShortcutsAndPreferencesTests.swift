import Foundation
import OmanCore
import Testing
@testable import OmanUI

@MainActor
@Suite struct ShortcutsAndPreferencesTests {
    private let selection = SelectionCapture(app: Harness.slack, text: "rough text")
    private let combo = KeyCombo(keyCode: 15, modifiers: KeyCombo.control | KeyCombo.option)

    private func preparedHarness(styles: Int = 0) -> Harness {
        let harness = Harness()
        harness.styles.seed((0..<styles).map { WritingStyle(name: "Style \($0)") })
        return harness
    }

    private func setPreferences(_ harness: Harness, _ change: (inout AppPreferences) -> Void) throws {
        var preferences = try harness.settings.preferences()
        change(&preferences)
        try harness.settings.setPreferences(preferences)
    }

    // MARK: Key combinations

    @Test func comboReadsInMacModifierOrder() {
        let all = KeyCombo(keyCode: 15, modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control)
        #expect(all.displayString == "⌃⌥⇧⌘R")
        #expect(KeyCombo(keyCode: 36, modifiers: KeyCombo.command).displayString == "⌘↩")
    }

    @Test func comboNeedsAModifierUnlessItIsAFunctionKey() {
        #expect(!KeyCombo(keyCode: 15, modifiers: 0).isUsable)
        #expect(!KeyCombo(keyCode: 15, modifiers: KeyCombo.shift).isUsable)
        #expect(KeyCombo(keyCode: 122, modifiers: 0).isUsable)
        #expect(combo.isUsable)
    }

    @Test func copyAndPasteAreRecognised() {
        #expect(KeyCombo(keyCode: 8, modifiers: KeyCombo.command).isCopyOrPaste)
        #expect(KeyCombo(keyCode: 9, modifiers: KeyCombo.command).isCopyOrPaste)
        #expect(!KeyCombo(keyCode: 8, modifiers: KeyCombo.command | KeyCombo.shift).isCopyOrPaste)
        #expect(!combo.isCopyOrPaste)
    }

    @Test func comboIgnoresUnrelatedEventFlags() {
        let capsLock: UInt = 1 << 16
        #expect(KeyCombo(keyCode: 15, modifiers: combo.modifiers | capsLock) == combo)
    }

    @Test func actionsRoundTripThroughStorageKeys() {
        let id = UUID()
        for action in ShortcutAction.globalActions + ShortcutAction.panelActions + [.style(id)] {
            #expect(ShortcutAction(storageKey: action.storageKey) == action)
        }
        #expect(ShortcutAction(storageKey: "nonsense") == nil)
    }

    // MARK: Saved preferences

    @Test func olderSavedPreferencesKeepNewDefaults() throws {
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"keepsPanelOpen":true}"#.utf8))
        #expect(decoded.keepsPanelOpen)
        #expect(decoded.remembersStylePerApp)
        #expect(decoded.combo(for: .acceptResult) == AppPreferences().combo(for: .acceptResult))
    }

    @Test func clearedShortcutStaysClearedAfterSaving() throws {
        var preferences = AppPreferences()
        preferences.setCombo(nil, for: .acceptResult)
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: data).combo(for: .acceptResult) == nil)
    }

    @Test func globalShortcutsLeavePanelActionsOut() {
        var preferences = AppPreferences()
        preferences.setCombo(combo, for: .rewrite)
        #expect(preferences.globalShortcuts == [.rewrite: combo])
    }

    @Test func aSavedCopyOrPasteShortcutIsNeverRegistered() {
        var preferences = AppPreferences()
        preferences.setCombo(KeyCombo(keyCode: 8, modifiers: KeyCombo.command), for: .proofread)
        preferences.setCombo(combo, for: .rewrite)
        #expect(preferences.globalShortcuts == [.rewrite: combo])
    }

    // MARK: Global shortcuts in the panel

    @Test func rewriteShortcutRunsOnTheSelection() async {
        let harness = preparedHarness()
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.run(.rewrite)
        #expect(await eventually { panel.screen == .result })
        #expect(harness.writing.requests.first?.task == .rewrite(text: "rough text", instruction: nil))
    }

    @Test func proofreadShortcutWithoutSelectionStaysInCompose() {
        let harness = preparedHarness()
        let panel = harness.makePanel()
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))
        panel.run(.proofread)
        #expect(panel.screen == .compose)
        #expect(harness.writing.requests.isEmpty)
    }

    @Test func styleShortcutRewritesInThatStyle() async throws {
        let harness = preparedHarness(styles: 2)
        let target = try #require(harness.styles.styles.last)
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.run(.style(target.id))
        #expect(await eventually { panel.screen == .result })
        #expect(harness.writing.requests.first?.style == target)
    }

    @Test func composeShortcutOpensCompose() {
        let panel = preparedHarness().makePanel()
        panel.begin(with: selection)
        panel.run(.compose)
        #expect(panel.screen == .compose)
    }

    // MARK: Panel shortcuts

    @Test func acceptShortcutReplacesTheSelection() async throws {
        let harness = preparedHarness()
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.rewrite()
        #expect(await eventually { panel.screen == .result })
        let accept = try #require(AppPreferences().combo(for: .acceptResult))

        #expect(panel.handlePanelShortcut(accept))
        #expect(await eventually { harness.system.replaceCalls.count == 1 })
    }

    @Test func toggleShortcutShowsTheOriginal() async throws {
        let panel = preparedHarness().makePanel()
        panel.begin(with: selection)
        panel.rewrite()
        #expect(await eventually { panel.screen == .result })
        let toggle = try #require(AppPreferences().combo(for: .toggleOriginal))

        #expect(panel.handlePanelShortcut(toggle))
        #expect(panel.showOriginal)
    }

    @Test func panelShortcutsOnlyApplyToAResult() throws {
        let panel = preparedHarness().makePanel()
        panel.begin(with: selection)
        let accept = try #require(AppPreferences().combo(for: .acceptResult))
        #expect(!panel.handlePanelShortcut(accept))
    }

    // MARK: Pinned panel

    @Test func refreshingAPinnedPanelKeepsItPinned() {
        let harness = preparedHarness()
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.togglePin()
        panel.begin(with: selection, keepPinned: true)
        #expect(panel.isPinned)
        #expect(harness.presenter.pinnedValues.last == true)
    }

    @Test func preferenceStartsEveryPanelPinned() throws {
        let harness = preparedHarness()
        try setPreferences(harness) { $0.keepsPanelOpen = true }
        let panel = harness.makePanel()
        panel.begin(with: selection)
        #expect(panel.isPinned)
    }

    @Test func replacingWhilePinnedBringsThePanelBack() async {
        let harness = preparedHarness()
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.togglePin()
        panel.rewrite()
        #expect(await eventually { panel.screen == .result })
        panel.applyResult()
        #expect(await eventually { harness.presenter.showCount == 1 })
        #expect(panel.notice == "Replaced")
    }

    // MARK: Writing preferences

    @Test func requestsCarryWritingPreferences() async throws {
        let harness = preparedHarness()
        try setPreferences(harness) {
            $0.quality = .best
            $0.outputLanguage = "English"
            $0.customInstructions = "No exclamation marks."
        }
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.rewrite()
        #expect(await eventually { panel.screen == .result })
        let request = try #require(harness.writing.requests.first)
        #expect(request.quality == .best)
        #expect(request.outputLanguage == "English")
        #expect(request.customInstructions == "No exclamation marks.")
    }

    @Test func defaultStyleIsPreselected() throws {
        let harness = preparedHarness(styles: 2)
        let target = try #require(harness.styles.styles.last)
        try setPreferences(harness) { $0.defaultStyleID = target.id }
        let panel = harness.makePanel()
        panel.begin(with: selection)
        #expect(panel.selectedStyleID == target.id)
    }

    @Test func turningOffMemoryIgnoresTheLastStyle() throws {
        let harness = preparedHarness(styles: 1)
        let style = try #require(harness.styles.styles.first)
        try harness.styles.setLastStyleChoice(.style(style.id), forApp: "com.tinyspeck.slackmacgap")
        try setPreferences(harness) { $0.remembersStylePerApp = false }
        let panel = harness.makePanel()
        panel.begin(with: selection)
        #expect(panel.selectedStyleID == nil)
    }

    @Test func aShortcutRequestWaitsForTheDefaultScreen() async throws {
        let harness = preparedHarness()
        try setPreferences(harness) { $0.includesScreenByDefault = true }
        let panel = harness.makePanel()
        panel.begin(with: selection)
        // This is what the menu bar does for a global shortcut: run the action straight after begin.
        panel.run(.rewrite)
        #expect(panel.screen == .working)

        #expect(await eventually { panel.screen == .result })
        #expect(harness.writing.requests.count == 1)
        #expect(harness.writing.requests.first?.context.screenshot != nil)
    }

    @Test func screenIsIncludedWhenThatIsTheDefault() async throws {
        let harness = preparedHarness()
        try setPreferences(harness) { $0.includesScreenByDefault = true }
        let panel = harness.makePanel()
        panel.begin(with: selection)
        #expect(panel.includeScreen)
        #expect(await eventually { panel.screenshot != nil })
    }

    // MARK: On-device model

    @Test func localModelNeedsNoAPIKey() async throws {
        let harness = Harness(key: nil)
        try harness.settings.setSelectedModel(.appleOnDevice)
        let panel = harness.makePanel()
        panel.begin(with: selection)
        #expect(panel.screen == .home)

        panel.rewrite()
        #expect(await eventually { panel.screen == .result })
        #expect(harness.writing.keys == [""])
        #expect(harness.writing.requests.first?.model == .appleOnDevice)
    }

    @Test func setupOffersTheLocalModelInsteadOfAKey() {
        let harness = Harness(key: nil)
        let panel = harness.makePanel()
        panel.begin(with: selection)
        #expect(panel.screen == .setup)
        #expect(panel.canUseAppleModel)

        panel.useAppleModel()
        #expect(panel.screen == .home)
    }

    @Test func screenIsNeverIncludedForTheLocalModel() throws {
        let harness = preparedHarness()
        try harness.settings.setSelectedModel(.appleOnDevice)
        try setPreferences(harness) { $0.includesScreenByDefault = true }
        let panel = harness.makePanel()
        panel.begin(with: selection)
        #expect(!panel.includeScreen)
    }

    @Test func unavailableLocalModelCannotBeSelected() {
        let harness = preparedHarness()
        harness.writing.scriptUnavailable("Turn on Apple Intelligence.")
        let settings = harness.makeSettings()
        settings.reload()
        settings.setModel(.appleOnDevice)
        #expect(settings.selectedModel == .default)
        #expect(settings.modelError == "Turn on Apple Intelligence.")
    }

    // MARK: Settings

    @Test func recordingSuspendsThenRegistersTheNewShortcut() {
        let harness = preparedHarness()
        let settings = harness.makeSettings()
        settings.reload()
        settings.startRecording(.rewrite)
        #expect(harness.system.suspendCount == 1)

        settings.finishRecording(with: combo)
        #expect(settings.recordingAction == nil)
        #expect(settings.preferences.combo(for: .rewrite) == combo)
        #expect(harness.system.registered == [.rewrite: combo])
    }

    @Test func cancellingRecordingRestoresShortcuts() throws {
        let harness = preparedHarness()
        try setPreferences(harness) { $0.setCombo(combo, for: .compose) }
        let settings = harness.makeSettings()
        settings.reload()
        settings.startRecording(.rewrite)
        settings.cancelRecording()
        #expect(harness.system.registered == [.compose: combo])
    }

    @Test func aComboMovesFromTheActionThatHadIt() throws {
        let harness = preparedHarness()
        try setPreferences(harness) { $0.setCombo(combo, for: .compose) }
        let settings = harness.makeSettings()
        settings.reload()
        settings.startRecording(.rewrite)
        settings.finishRecording(with: combo)

        #expect(settings.preferences.combo(for: .compose) == nil)
        #expect(settings.preferences.combo(for: .rewrite) == combo)
        #expect(settings.shortcutNotice == "\(combo.displayString) moved here from Compose.")
    }

    @Test func copyAndPasteCannotBecomeShortcuts() throws {
        let harness = preparedHarness()
        try setPreferences(harness) { $0.setCombo(combo, for: .compose) }
        let settings = harness.makeSettings()
        settings.reload()
        settings.startRecording(.rewrite)
        settings.finishRecording(with: KeyCombo(keyCode: 9, modifiers: KeyCombo.command))

        #expect(settings.recordingAction == nil)
        #expect(settings.preferences.combo(for: .rewrite) == nil)
        #expect(settings.shortcutNotice == "⌘V is how OmanAI copies and pastes, so it can't be a shortcut.")
        // Recording had suspended the shortcuts, so the saved ones come back.
        #expect(harness.system.registered == [.compose: combo])
    }

    @Test func aCopyOrPasteShortcutFromAnEarlierVersionIsShownAsFailed() throws {
        let harness = preparedHarness()
        try setPreferences(harness) {
            $0.setCombo(KeyCombo(keyCode: 9, modifiers: KeyCombo.command), for: .proofread)
            $0.setCombo(combo, for: .rewrite)
        }
        let settings = harness.makeSettings()
        settings.reload()
        #expect(settings.failedShortcuts == [.proofread])

        settings.clearShortcut(for: .proofread)
        #expect(settings.failedShortcuts.isEmpty)
        #expect(harness.system.registered == [.rewrite: combo])
    }

    @Test func aRejectedShortcutIsReported() {
        let harness = preparedHarness()
        harness.system.rejected = [.rewrite]
        let settings = harness.makeSettings()
        settings.reload()
        settings.startRecording(.rewrite)
        settings.finishRecording(with: combo)
        #expect(settings.failedShortcuts == [.rewrite])
    }

    @Test func clearingRemovesTheShortcut() throws {
        let harness = preparedHarness()
        try setPreferences(harness) { $0.setCombo(combo, for: .rewrite) }
        let settings = harness.makeSettings()
        settings.reload()
        settings.clearShortcut(for: .rewrite)
        #expect(settings.preferences.combo(for: .rewrite) == nil)
        #expect(harness.system.registered.isEmpty)
    }

    @Test func deletingAStyleRemovesItsShortcutAndDefault() throws {
        let harness = preparedHarness(styles: 1)
        let style = try #require(harness.styles.styles.first)
        try setPreferences(harness) {
            $0.setCombo(combo, for: .style(style.id))
            $0.defaultStyleID = style.id
        }
        let settings = harness.makeSettings()
        settings.reload()
        settings.selectStyle(style.id)
        settings.deleteSelectedStyle()

        #expect(settings.preferences.combo(for: .style(style.id)) == nil)
        #expect(settings.preferences.defaultStyleID == nil)
        #expect(harness.system.registered.isEmpty)
    }

    @Test func eachStyleGetsAShortcutRow() {
        let harness = preparedHarness(styles: 2)
        let settings = harness.makeSettings()
        settings.reload()
        #expect(settings.globalShortcutActions.count == ShortcutAction.globalActions.count + 2)
    }

    @Test func appearanceIsAppliedAndSaved() throws {
        let harness = preparedHarness()
        let settings = harness.makeSettings()
        settings.reload()
        settings.setAppearance(.dark)
        #expect(harness.system.appearance == .dark)
        #expect(try harness.settings.preferences().appearance == .dark)
    }
}
