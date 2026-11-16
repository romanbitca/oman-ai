import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

/// The pill's model switch: a chip after the seconds that shows the model listening, and a list of the models that
/// are ready to listen instead.
@MainActor
@Suite struct DictationModelSwitchTests {
    private func listening(_ harness: Harness, _ controller: DictationController) async throws -> FakeDictationSession {
        #expect(await eventually { controller.phase == .listening })
        return try #require(harness.speech.sessions.last)
    }

    /// Only these models are downloaded; every other one needs a download first.
    private func onlyReady(_ ready: [DictationModel], in harness: Harness) {
        for model in DictationModel.allCases where !ready.contains(model) {
            harness.speech.setStatus(.needsDownload(bytes: nil), for: model)
        }
    }

    private func set(_ harness: Harness, _ change: (inout AppPreferences) -> Void) throws {
        var preferences = try harness.settings.preferences()
        change(&preferences)
        try harness.settings.setPreferences(preferences)
    }

    @Test func theSwitchOffersTheModelsThatAreReady() async throws {
        let harness = Harness()
        onlyReady([.apple, .parakeetEnglish, .whisper], in: harness)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        _ = try await listening(harness, controller)
        #expect(await eventually { controller.readyModels == [.apple, .parakeetEnglish, .whisper] })
        #expect(controller.offersModelSwitch)
        #expect(controller.listeningModel == .apple)
    }

    @Test func withOneModelReadyThereIsNothingToSwitchTo() async throws {
        let harness = Harness()
        onlyReady([.apple], in: harness)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        _ = try await listening(harness, controller)
        #expect(await eventually { controller.readyModels == [.apple] })
        #expect(!controller.offersModelSwitch)
    }

    @Test func turnedOffInSettingsTheSwitchNeverShows() async throws {
        let harness = Harness()
        try set(harness) { $0.showsModelSwitch = false }
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        _ = try await listening(harness, controller)
        #expect(controller.readyModels.isEmpty)
        #expect(!controller.offersModelSwitch)
    }

    @Test func switchingWhileListeningKeepsTheWordsAndListensWithTheNewModel() async throws {
        let harness = Harness()
        onlyReady([.apple, .parakeetEnglish], in: harness)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let first = try await listening(harness, controller)
        #expect(await eventually { controller.offersModelSwitch })
        first.send(.transcript(LiveTranscript(confirmed: "Hello there")))
        #expect(await eventually { controller.transcript.text == "Hello there" })

        first.willFinish(with: "Hello there")
        controller.switchModel(to: .parakeetEnglish)
        #expect(controller.listeningModel == .parakeetEnglish)
        #expect(try harness.settings.preferences().dictationModel == .parakeetEnglish)
        #expect(await eventually { harness.speech.sessions.count == 2 })
        #expect(first.finished)
        #expect(harness.speech.starts.last?.model == .parakeetEnglish)
        #expect(controller.phase == .listening)

        // The new model's words follow the old one's, on screen and in what goes in.
        let second = try #require(harness.speech.sessions.last)
        second.send(.transcript(LiveTranscript(confirmed: "how are you")))
        #expect(await eventually { controller.transcript.text == "Hello there how are you" })
        second.willFinish(with: "how are you")
        controller.finishNow()
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["Hello there how are you"])
        #expect(harness.dictations.saved.first?.model == DictationModel.parakeetEnglish.rawValue)

        // The next dictation starts with the model chosen in the pill.
        controller.longPressed(into: nil)
        _ = try await listening(harness, controller)
        #expect(harness.speech.starts.last?.model == .parakeetEnglish)
    }

    @Test func doneWhileSwitchingPutsInWhatWasHeardAndStartsNothing() async throws {
        let harness = Harness()
        onlyReady([.apple, .whisper], in: harness)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let first = try await listening(harness, controller)
        #expect(await eventually { controller.offersModelSwitch })
        first.willFinish(with: "Just this")
        controller.switchModel(to: .whisper)
        controller.finishNow()
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["Just this"])
        #expect(harness.speech.sessions.count == 1)
    }

    @Test func cancelWhileSwitchingPutsInNothing() async throws {
        let harness = Harness()
        onlyReady([.apple, .whisper], in: harness)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let first = try await listening(harness, controller)
        #expect(await eventually { controller.offersModelSwitch })
        first.willFinish(with: "Never mind")
        controller.switchModel(to: .whisper)
        controller.cancel()
        #expect(controller.phase == .idle)
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.system.insertCalls.isEmpty)
        #expect(harness.speech.sessions.allSatisfy { $0.finished || $0.cancelled })
        #expect(controller.phase == .idle)
    }

    @Test func aModelThatIsNotReadyCannotBeChosen() async throws {
        let harness = Harness()
        onlyReady([.apple, .whisper], in: harness)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        _ = try await listening(harness, controller)
        #expect(await eventually { controller.offersModelSwitch })
        controller.switchModel(to: .parakeet)
        #expect(controller.listeningModel == .apple)
        #expect(harness.speech.sessions.count == 1)
        #expect(try harness.settings.preferences().dictationModel == .apple)
    }

    @Test func aSettingFromAnOlderVersionShowsTheSwitch() throws {
        let older = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"quality":"fast"}"#.utf8))
        #expect(older.showsModelSwitch)
    }

    @Test func everyModelHasAShortNameForTheChip() {
        for model in DictationModel.allCases {
            #expect(model.shortName.count <= 14)
        }
    }
}
