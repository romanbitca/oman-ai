import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

@MainActor
@Suite struct DictationControllerTests {
    private func listening(_ harness: Harness, _ controller: DictationController) async throws -> FakeDictationSession {
        #expect(await eventually { controller.phase == .listening })
        return try #require(harness.speech.sessions.last)
    }

    @Test func holdingTheShortcutPastesWhatWasSaidWhenItIsLetGo() async throws {
        let harness = Harness()
        let controller = harness.makeDictation()

        controller.holdPressed(into: nil)
        #expect(controller.phase == .starting)
        #expect(harness.dictationPresenter.shownAt == [.menuBar])
        #expect(harness.system.temporary[.cancelDictation] == DictationController.escape)
        let session = try await listening(harness, controller)

        session.send(.transcript(LiveTranscript(confirmed: "Hello", tentative: "wor")))
        #expect(await eventually { controller.transcript.text == "Hello wor" })
        session.send(.level(0.6))
        #expect(await eventually { controller.level == 0.6 })

        session.willFinish(with: " Hello world. ")
        controller.holdReleased()
        #expect(await eventually { controller.phase == .idle })

        #expect(harness.system.insertCalls.map(\.text) == ["Hello world."])
        #expect(harness.system.insertCalls.first?.app == nil)
        #expect(harness.dictations.saved.map(\.text) == ["Hello world."])
        #expect(harness.dictations.saved.first?.appName == "Slack")
        #expect(harness.dictations.saved.first?.model == DictationModel.apple.rawValue)
        #expect(harness.dictations.saved.first?.language == "en-US")
        #expect(harness.system.temporary[.cancelDictation] == nil)
        #expect(!harness.dictationPresenter.isShowing)
        #expect(harness.dictationPresenter.activeValues == [true, false])
    }

    @Test func lettingGoBeforeTheMicrophoneIsReadyFinishesAsSoonAsItIs() async throws {
        let harness = Harness()
        let controller = harness.makeDictation()

        controller.holdPressed(into: nil)
        controller.holdReleased()
        #expect(await eventually { harness.speech.sessions.last?.finished == true })
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.isEmpty)
        #expect(harness.dictations.saved.isEmpty)
    }

    @Test func theLongShortcutStartsAndFinishes() async throws {
        let harness = Harness()
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        #expect(controller.mode == .long)

        // Holding the other shortcut meanwhile changes nothing.
        controller.holdPressed(into: nil)
        controller.holdReleased()
        #expect(controller.phase == .listening)

        session.willFinish(with: "A longer thought")
        controller.longPressed(into: nil)
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["A longer thought"])
    }

    @Test func escapeThrowsTheWordsAway() async throws {
        let harness = Harness()
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        session.send(.transcript(LiveTranscript(confirmed: "Never mind")))
        controller.cancel()

        #expect(controller.phase == .idle)
        #expect(await eventually { session.cancelled })
        #expect(harness.system.insertCalls.isEmpty)
        #expect(harness.dictations.saved.isEmpty)
        #expect(!harness.dictationPresenter.isShowing)
        #expect(harness.system.temporary[.cancelDictation] == nil)
    }

    @Test func thePillShowsWhereSettingsPutsIt() async throws {
        let harness = Harness()
        var preferences = AppPreferences()
        preferences.dictationPillPosition = .bottom
        try harness.settings.setPreferences(preferences)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        #expect(harness.dictationPresenter.shownAt == [.bottom])
        #expect(controller.position == .bottom)
        controller.cancel()
    }

    @Test func wordsForThePanelAppearInItsFieldAsTheyAreSaid() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        let controller = harness.makeDictation(panel: panel)
        panel.composePrompt = "Reply to Ana:"

        controller.longPressed(into: .composePrompt)
        #expect(harness.dictationPresenter.shownAt.isEmpty)
        let session = try await listening(harness, controller)

        session.send(.transcript(LiveTranscript(confirmed: "thanks for", tentative: "the")))
        #expect(await eventually { panel.composePrompt == "Reply to Ana: thanks for the" })

        session.willFinish(with: "thanks for the notes.")
        controller.longPressed(into: .composePrompt)
        #expect(await eventually { controller.phase == .idle })
        #expect(panel.composePrompt == "Reply to Ana: thanks for the notes.")
        #expect(harness.system.insertCalls.isEmpty)
        #expect(harness.dictations.saved.first?.appName == "OmanAI")
    }

    @Test func cancellingADictationIntoThePanelPutsTheFieldBack() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        let controller = harness.makeDictation(panel: panel)
        panel.adjustment = "shorter"

        controller.toggle(into: .adjustment)
        let session = try await listening(harness, controller)
        session.send(.transcript(LiveTranscript(confirmed: "and warmer")))
        #expect(await eventually { panel.adjustment == "shorter and warmer" })

        controller.cancel()
        #expect(panel.adjustment == "shorter")
    }

    @Test func closingThePanelStopsADictationIntoIt() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        let controller = harness.makeDictation(panel: panel)

        controller.toggle(into: .instruction)
        let session = try await listening(harness, controller)
        panel.panelDidClose()

        #expect(controller.phase == .idle)
        #expect(await eventually { session.cancelled })
    }

    @Test func theMicrophoneIsAskedForTheFirstTime() async throws {
        let harness = Harness()
        harness.system.microphoneAccess = .notDetermined
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        _ = try await listening(harness, controller)
        #expect(harness.system.microphoneRequests == 1)
        controller.cancel()
    }

    @Test(arguments: [MicrophoneAccess.denied, .notDetermined])
    func withoutTheMicrophoneThePillSaysWhy(access: MicrophoneAccess) async throws {
        let harness = Harness()
        harness.system.microphoneAccess = access
        harness.system.microphoneAnswer = false
        let controller = harness.makeDictation()

        controller.holdPressed(into: nil)
        #expect(await eventually { controller.phase == .idle })
        #expect(controller.notice == DictationError.microphoneDenied.message)
        #expect(harness.dictationPresenter.isShowing)
        #expect(harness.speech.sessions.isEmpty)
        #expect(harness.system.temporary[.cancelDictation] == nil)
    }

    @Test func aModelStillToDownloadSaysSo() async throws {
        let harness = Harness()
        var preferences = AppPreferences()
        preferences.dictationModel = .whisper
        try harness.settings.setPreferences(preferences)
        harness.speech.setStatus(.needsDownload(bytes: 600_000_000), for: .whisper)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        #expect(await eventually { controller.phase == .idle })
        #expect(controller.notice == DictationError.modelNotReady(.whisper).message)
        #expect(harness.speech.sessions.isEmpty)
    }

    @Test func theChosenLanguageIsTheOneListenedFor() async throws {
        let harness = Harness()
        var preferences = AppPreferences()
        preferences.dictationModel = .parakeet
        preferences.setDictationLanguage(DictationLanguage(id: "ro"), for: .parakeet)
        preferences.setDictationLanguage(DictationLanguage(id: "en-US"), for: .apple)
        try harness.settings.setPreferences(preferences)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        _ = try await listening(harness, controller)
        #expect(harness.speech.starts.first?.model == .parakeet)
        #expect(harness.speech.starts.first?.language == DictationLanguage(id: "ro"))
        controller.cancel()
    }

    @Test func wordsThatCannotBePastedAreCopied() async throws {
        let harness = Harness()
        harness.system.insertOutcome = .sourceUnavailable
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        session.willFinish(with: "Keep this")
        controller.finishNow()

        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.copied == ["Keep this"])
        #expect(controller.notice == "There was nowhere to paste, so your words were copied.")
        #expect(harness.dictations.saved.map(\.text) == ["Keep this"])
    }

    @Test func transcriptsAreNotKeptWhenSettingsSaysNot() async throws {
        let harness = Harness()
        var preferences = AppPreferences()
        preferences.keepsDictations = false
        try harness.settings.setPreferences(preferences)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        session.willFinish(with: "Private")
        controller.finishNow()

        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["Private"])
        #expect(harness.dictations.saved.isEmpty)
    }

    @Test func aModelThatFailsToStartSaysWhy() async throws {
        let harness = Harness()
        harness.speech.failStart(with: DictationError.noMicrophone)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        #expect(await eventually { controller.phase == .idle })
        #expect(controller.notice == DictationError.noMicrophone.message)
    }

    @Test func thePanelOffersTheFieldOfTheScreenItShows() {
        let harness = Harness()
        let panel = harness.makePanel()
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))
        #expect(panel.dictationField == .composePrompt)
        panel.begin(with: SelectionCapture(app: Harness.slack, text: "Some text"))
        #expect(panel.dictationField == .instruction)
    }
}
