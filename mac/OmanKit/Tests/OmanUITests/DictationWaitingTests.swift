import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

/// Dictated words when nothing that takes text has the cursor in the app in front: they wait in the pill until a
/// field gets the cursor, Copy, × or Escape is pressed, or a minute passes.
@MainActor
@Suite struct DictationWaitingTests {
    private static let words = "Meet at noon"

    private func makeController(_ harness: Harness, panel: PanelViewModel? = nil) -> DictationController {
        let controller = harness.makeDictation(panel: panel)
        controller.holdTiming = .init(checkEvery: .milliseconds(10), giveUpAfter: .seconds(30))
        return controller
    }

    private func set(_ harness: Harness, _ change: (inout AppPreferences) -> Void) throws {
        var preferences = AppPreferences()
        change(&preferences)
        try harness.settings.setPreferences(preferences)
    }

    /// A long dictation into the app in front, finished with these words.
    private func dictate(
        _ harness: Harness,
        _ controller: DictationController,
        saying words: String = Self.words
    ) async throws {
        controller.longPressed(into: nil)
        #expect(await eventually { controller.phase == .listening })
        let session = try #require(harness.speech.sessions.last)
        session.willFinish(with: words)
        controller.finishNow()
    }

    /// Dictates where nothing takes text, and waits until the words are held.
    private func dictateIntoNowhere(
        _ harness: Harness,
        _ controller: DictationController,
        saying words: String = Self.words
    ) async throws {
        harness.system.focus = .cannotTakeText
        try await dictate(harness, controller, saying: words)
        #expect(await eventually { controller.phase == .holding })
    }

    // MARK: The three answers

    @Test func aFieldThatTakesTextGetsTheWordsAtOnce() async throws {
        let harness = Harness()
        let controller = makeController(harness)

        controller.longPressed(into: nil)
        #expect(await eventually { controller.phase == .listening })
        // Asked when the words are ready to go in, not before.
        #expect(harness.system.focusChecks == 0)
        let session = try #require(harness.speech.sessions.last)
        session.willFinish(with: Self.words)
        controller.finishNow()

        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.focusChecks == 1)
        #expect(harness.system.insertCalls.map(\.text) == [Self.words])
        #expect(harness.system.copied.isEmpty)
        #expect(!harness.dictationPresenter.isShowing)
    }

    @Test func anAppThatCannotSayIsPastedIntoAsBefore() async throws {
        let harness = Harness()
        harness.system.focus = .unknown
        let controller = makeController(harness)

        try await dictate(harness, controller)
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == [Self.words])
        #expect(harness.system.copied.isEmpty)
        #expect(controller.notice == nil)
    }

    @Test func whereNothingTakesTextTheWordsWaitInThePill() async throws {
        let harness = Harness()
        let controller = makeController(harness)

        try await dictateIntoNowhere(harness, controller)
        #expect(harness.system.insertCalls.isEmpty)
        #expect(harness.system.copied.isEmpty)
        #expect(controller.transcript.text == Self.words)
        #expect(harness.dictationPresenter.isShowing)
        // The transcript is kept as usual, whatever happens to the words next.
        #expect(harness.dictations.saved.map(\.text) == [Self.words])
        #expect(harness.dictations.saved.first?.appName == "Slack")
        // Escape still cancels, while the menu bar icon is still again.
        #expect(harness.system.temporary[.cancelDictation] == DictationController.escape)
        #expect(!controller.isActive)
        #expect(harness.dictationPresenter.activeValues.last == false)
        controller.cancel()
    }

    // MARK: A field gets the cursor

    @Test func theWordsGoInWhenAFieldGetsTheCursor() async throws {
        let harness = Harness()
        let controller = makeController(harness)

        try await dictateIntoNowhere(harness, controller)
        #expect(await eventually { harness.system.focusChecks >= 4 })
        #expect(controller.phase == .holding)
        #expect(harness.system.insertCalls.isEmpty)

        harness.system.focus = .takesText
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == [Self.words])
        #expect(harness.system.insertCalls.first?.app == nil)
        #expect(!harness.dictationPresenter.isShowing)
        #expect(harness.system.copied.isEmpty)
        #expect(controller.notice == nil)
        #expect(harness.system.temporary[.cancelDictation] == nil)
        #expect(harness.dictations.saved.count == 1)
    }

    @Test func anAppThatCannotSayNeverTakesWaitingWords() async throws {
        let harness = Harness()
        let controller = makeController(harness)

        try await dictateIntoNowhere(harness, controller)
        harness.system.focus = .unknown
        let checks = harness.system.focusChecks
        #expect(await eventually { harness.system.focusChecks >= checks + 4 })
        #expect(controller.phase == .holding)
        #expect(harness.system.insertCalls.isEmpty)
        controller.cancel()
    }

    @Test func aLatePasteAddsTheSpaceAndPressesReturn() async throws {
        let harness = Harness()
        try set(harness) {
            $0.addsSpaceAfterDictation = true
            $0.dictationSubmit = .commandReturn
        }
        let controller = makeController(harness)

        try await dictateIntoNowhere(harness, controller, saying: "Ship it")
        harness.system.focus = .takesText
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["Ship it "])
        #expect(harness.system.returnPresses == [true])
        // The transcript is the words alone.
        #expect(harness.dictations.saved.map(\.text) == ["Ship it"])
    }

    @Test func returnIsNotPressedWhenALatePasteCannotGoIn() async throws {
        let harness = Harness()
        try set(harness) { $0.dictationSubmit = .returnKey }
        let controller = makeController(harness)

        try await dictateIntoNowhere(harness, controller)
        harness.system.insertOutcome = .sourceUnavailable
        harness.system.focus = .takesText
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.returnPresses.isEmpty)
        #expect(harness.system.copied == [Self.words])
        #expect(controller.notice == DictationController.copiedNotice)
    }

    // MARK: Copy, ×, Escape and the minute

    @Test func copyCopiesTheWordsAndClosesThePill() async throws {
        let harness = Harness()
        let controller = makeController(harness)

        try await dictateIntoNowhere(harness, controller)
        controller.copyHeldWords()
        #expect(controller.phase == .idle)
        #expect(harness.system.copied == [Self.words])
        #expect(!harness.dictationPresenter.isShowing)
        #expect(controller.notice == nil)
        #expect(harness.system.temporary[.cancelDictation] == nil)

        // Nothing goes in afterwards, even where a field gets the cursor.
        harness.system.focus = .takesText
        try await Task.sleep(for: .milliseconds(80))
        #expect(harness.system.insertCalls.isEmpty)
    }

    /// × in the pill and Escape both cancel.
    @Test func cancellingThrowsTheWordsAwayButKeepsTheTranscript() async throws {
        let harness = Harness()
        let controller = makeController(harness)

        try await dictateIntoNowhere(harness, controller)
        controller.cancel()
        #expect(controller.phase == .idle)
        #expect(harness.system.copied.isEmpty)
        #expect(!harness.dictationPresenter.isShowing)
        #expect(harness.system.temporary[.cancelDictation] == nil)
        #expect(harness.dictations.saved.map(\.text) == [Self.words])
        #expect(controller.lastText == Self.words)

        harness.system.focus = .takesText
        try await Task.sleep(for: .milliseconds(80))
        #expect(harness.system.insertCalls.isEmpty)
    }

    @Test func afterAMinuteTheWordsAreCopiedWithANotice() async throws {
        let harness = Harness()
        let controller = makeController(harness)
        controller.holdTiming = .init(checkEvery: .milliseconds(10), giveUpAfter: .milliseconds(150))

        try await dictateIntoNowhere(harness, controller)
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.copied == [Self.words])
        #expect(harness.system.insertCalls.isEmpty)
        #expect(controller.notice == DictationController.waitedNotice)
        // The notice shows in the pill for a moment before it closes.
        #expect(harness.dictationPresenter.isShowing)
        #expect(harness.system.temporary[.cancelDictation] == nil)
    }

    // MARK: Something else meanwhile

    @Test func openingThePanelCopiesTheWaitingWords() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        let controller = makeController(harness, panel: panel)

        try await dictateIntoNowhere(harness, controller)
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))
        #expect(controller.phase == .idle)
        #expect(harness.system.copied == [Self.words])
        #expect(!harness.dictationPresenter.isShowing)
        #expect(panel.hasLastTranscript)
    }

    @Test func aNewDictationCopiesTheWaitingWordsFirst() async throws {
        let harness = Harness()
        let controller = makeController(harness)

        try await dictateIntoNowhere(harness, controller)
        controller.holdPressed(into: nil)
        #expect(harness.system.copied == [Self.words])
        #expect(controller.mode == .hold)
        #expect(await eventually { controller.phase == .listening })
        #expect(controller.transcript.isEmpty)
        #expect(harness.dictationPresenter.isShowing)
        #expect(harness.dictationPresenter.activeValues.last == true)

        // The earlier words no longer wait for a field.
        harness.system.focus = .takesText
        try await Task.sleep(for: .milliseconds(80))
        #expect(harness.system.insertCalls.isEmpty)
        controller.cancel()
    }

    @Test func aDictationIntoThePanelCopiesTheWaitingWordsAndHidesThePill() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        let controller = makeController(harness, panel: panel)

        try await dictateIntoNowhere(harness, controller)
        controller.toggle(into: .composePrompt)
        #expect(harness.system.copied == [Self.words])
        #expect(controller.field == .composePrompt)
        #expect(!harness.dictationPresenter.isShowing)
        controller.cancel()
    }

    @Test func aKeyOnItsOwnStartsANewDictationWhileWordsWait() async throws {
        let harness = Harness()
        var preferences = AppPreferences()
        preferences.dictationHoldKey = .rightOption
        try harness.settings.setPreferences(preferences)
        let controller = makeController(harness)
        let keys = ModifierKeyDictation(controller: controller, preferences: { preferences }, holdDelay: .milliseconds(20))

        try await dictateIntoNowhere(harness, controller)
        keys.handle(.down(.rightOption)) { nil }
        #expect(await eventually { controller.phase == .listening })
        #expect(controller.mode == .hold)
        #expect(harness.system.copied == [Self.words])
        controller.cancel()
    }
}
