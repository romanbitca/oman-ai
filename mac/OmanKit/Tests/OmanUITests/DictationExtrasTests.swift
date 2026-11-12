import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

/// What happens around a dictation: sounds, muting, the microphone, Return, the transcripts kept, the ✨ button
/// and Copy last transcript.
@MainActor
@Suite struct DictationExtrasTests {
    private func listening(_ harness: Harness, _ controller: DictationController) async throws -> FakeDictationSession {
        #expect(await eventually { controller.phase == .listening })
        return try #require(harness.speech.sessions.last)
    }

    private func set(_ harness: Harness, _ change: (inout AppPreferences) -> Void) throws {
        var preferences = AppPreferences()
        change(&preferences)
        try harness.settings.setPreferences(preferences)
    }

    @Test func soundsPlayAndTheMacIsMutedOnlyWhileListening() async throws {
        let harness = Harness()
        try set(harness) {
            $0.playsDictationSounds = true
            $0.mutesAudioWhileDictating = true
        }
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        #expect(harness.system.sounds == [.start])
        #expect(harness.system.mutes == [true])

        session.willFinish(with: "Hi")
        controller.finishNow()
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.sounds == [.start, .finish])
        #expect(harness.system.mutes == [true, false])
    }

    @Test func cancellingBringsTheSoundBackWithoutTheFinishSound() async throws {
        let harness = Harness()
        try set(harness) {
            $0.playsDictationSounds = true
            $0.mutesAudioWhileDictating = true
        }
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        _ = try await listening(harness, controller)
        controller.cancel()
        #expect(controller.phase == .idle)
        #expect(harness.system.sounds == [.start])
        #expect(harness.system.mutes == [true, false])
    }

    @Test func nothingIsPlayedOrMutedByDefault() async throws {
        let harness = Harness()
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        session.willFinish(with: "Hi")
        controller.finishNow()
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.sounds.isEmpty)
        #expect(harness.system.mutes.isEmpty)
        #expect(harness.system.returnPresses.isEmpty)
        #expect(harness.system.insertCalls.map(\.text) == ["Hi"])
    }

    @Test func theMicrophoneChosenInSettingsListens() async throws {
        let harness = Harness()
        try set(harness) { $0.dictationMicrophone = "USB-1" }
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        _ = try await listening(harness, controller)
        #expect(harness.speech.microphonesUsed == ["USB-1"])
        controller.cancel()
    }

    @Test func aSpaceGoesAfterTheWordsAndReturnIsPressed() async throws {
        let harness = Harness()
        try set(harness) {
            $0.addsSpaceAfterDictation = true
            $0.dictationSubmit = .commandReturn
        }
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        session.willFinish(with: "Ship it")
        controller.finishNow()
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["Ship it "])
        #expect(harness.system.returnPresses == [true])
        // The transcript is the words alone.
        #expect(harness.dictations.saved.map(\.text) == ["Ship it"])
    }

    @Test func returnIsNotPressedWhenTheWordsCouldNotGoIn() async throws {
        let harness = Harness()
        harness.system.insertOutcome = .focusMoved
        try set(harness) { $0.dictationSubmit = .returnKey }
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        session.willFinish(with: "Ship it")
        controller.finishNow()
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.returnPresses.isEmpty)
        #expect(harness.system.copied == ["Ship it"])
    }

    @Test func onlyTheNewestTranscriptsAreKept() async throws {
        let harness = Harness()
        try set(harness) { $0.dictationHistory = .last10 }
        let old = (0..<12).map { index in
            SavedDictation(
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                text: "Old \(index)",
                duration: 1,
                model: "apple",
                language: nil,
                appName: nil
            )
        }
        harness.dictations.seed(old)
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        session.willFinish(with: "Newest")
        controller.finishNow()
        #expect(await eventually { controller.phase == .idle })
        let kept = try harness.dictations.savedDictations()
        #expect(kept.count == 10)
        #expect(kept.first?.text == "Newest")
        #expect(!kept.contains { $0.text == "Old 0" })
    }

    @Test func keepingFewerTranscriptsDeletesTheOldestAtOnce() throws {
        let harness = Harness()
        harness.dictations.seed((0..<14).map { index in
            SavedDictation(
                date: Date(timeIntervalSince1970: TimeInterval(index)), text: "Said \(index)", duration: 1,
                model: "apple", language: nil, appName: nil
            )
        })
        let settings = harness.makeSettings()
        settings.reload()
        settings.reloadSavedDictations()

        #expect(settings.transcriptsDeleted(by: .all) == 0)
        #expect(settings.transcriptsDeleted(by: .last50) == 0)
        #expect(settings.transcriptsDeleted(by: .last10) == 4)
        // None stops keeping more, and leaves the ones there are.
        #expect(settings.transcriptsDeleted(by: .off) == 0)

        settings.setDictationHistory(.last10)
        #expect(settings.savedDictations.count == 10)
        #expect(settings.savedDictations.first?.text == "Said 13")
        #expect((try? harness.settings.preferences())?.dictationHistory == .last10)

        settings.setDictationHistory(.off)
        #expect(settings.savedDictations.count == 10)
    }

    // MARK: The ✨ button

    @Test func improveOpensThePanelWithTheWordsInsteadOfPastingThem() async throws {
        let harness = Harness()
        let controller = harness.makeDictation()

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        session.willFinish(with: "hey can u send it")
        controller.improveNow()
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.isEmpty)
        #expect(harness.dictationPresenter.panelOpenings.map(\.text) == ["hey can u send it"])
        #expect(harness.dictationPresenter.panelOpenings.first?.app == Harness.slack)
        #expect(!harness.dictationPresenter.isShowing)
        #expect(harness.dictations.saved.map(\.text) == ["hey can u send it"])
        #expect(controller.lastText == "hey can u send it")
    }

    @Test func improveIsOnlyForAnotherApp() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        let controller = harness.makeDictation(panel: panel)
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))

        controller.toggle(into: .composePrompt)
        let session = try await listening(harness, controller)
        controller.improveNow()
        #expect(controller.phase == .listening)
        session.willFinish(with: "Words")
        controller.finishNow()
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.dictationPresenter.panelOpenings.isEmpty)
    }

    @Test func dictatedWordsInThePanelGoInAtTheCursor() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        _ = harness.makeDictation(panel: panel)

        panel.begin(withDictatedText: "hey can u send it", from: Harness.slack)
        #expect(harness.system.focusRemembered == [Harness.slack])
        #expect(panel.screen == .home)
        #expect(panel.capture.text == "hey can u send it")
        panel.proofread()
        await panel.runningTask?.value
        #expect(panel.screen == .result)
        #expect(panel.primaryActionTitle == "Insert")

        panel.applyResult()
        await panel.runningTask?.value
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(harness.system.insertCalls.map(\.text) == ["Hello world"])
        #expect(harness.system.insertCalls.first?.app == Harness.slack)

        // An ordinary selection afterwards is replaced again.
        panel.begin(with: SelectionCapture(app: Harness.slack, text: "Some text"))
        #expect(panel.primaryActionTitle == "Replace")
    }

    // MARK: Copy last transcript

    @Test func copyLastTranscriptCopiesTheLastDictation() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        let controller = harness.makeDictation(panel: panel)
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))
        #expect(!panel.hasLastTranscript)

        controller.longPressed(into: nil)
        let session = try await listening(harness, controller)
        session.willFinish(with: "Remember this")
        controller.finishNow()
        #expect(await eventually { controller.phase == .idle })

        #expect(panel.hasLastTranscript)
        panel.copyLastTranscript()
        #expect(harness.system.copied.last == "Remember this")
        #expect(panel.copiedTranscript)
    }

    @Test func copyLastTranscriptFallsBackToTheNewestKept() {
        let harness = Harness()
        harness.dictations.seed([
            SavedDictation(date: Date(timeIntervalSince1970: 1), text: "Older", duration: 1, model: "apple",
                           language: nil, appName: nil),
            SavedDictation(date: Date(timeIntervalSince1970: 2), text: "Newer", duration: 1, model: "apple",
                           language: nil, appName: nil),
        ])
        let panel = harness.makePanel()
        // The panel holds the controller weakly, as in the app.
        let controller = harness.makeDictation(panel: panel)
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))

        #expect(panel.hasLastTranscript)
        panel.copyLastTranscript()
        #expect(harness.system.copied == ["Newer"])
        #expect(controller.lastText == nil)
    }

    @Test func choosingAKeyStartsWatchingIt() {
        let harness = Harness()
        let settings = harness.makeSettings()
        settings.reload()

        settings.setDictationKey(.rightOption, for: .dictateHold)
        #expect(harness.system.watchedKeys == [.rightOption])
        settings.setDictationKey(.rightCommand, for: .dictateLong)
        #expect(harness.system.watchedKeys == [.rightOption, .rightCommand])
        #expect(settings.dictationKey(for: .dictateLong) == .rightCommand)
        settings.setDictationKey(nil, for: .dictateHold)
        #expect(harness.system.watchedKeys == [.rightCommand])
        #expect((try? harness.settings.preferences())?.dictationLongKey == .rightCommand)
    }

    @Test func languageFitIsSaidInPlainWords() {
        let locale = Locale(identifier: "en_US")
        #expect(DictationModel.languageFit(codes: ["en"], personLanguages: ["en", "ro"], locale: locale)
            == "English only")
        let european: Set<String> = ["en", "ro", "de", "fr"]
        #expect(DictationModel.languageFit(codes: european, personLanguages: ["en", "ro"], locale: locale)
            == "4 languages, including English and Romanian")
        #expect(DictationModel.languageFit(codes: european, personLanguages: ["en", "ja"], locale: locale)
            == "4 languages, including English but not Japanese")
        #expect(DictationModel.languageFit(codes: european, personLanguages: ["ja", "ko"], locale: locale)
            == "4 languages, but not Japanese or Korean")
        let many = Set((0..<99).map { "x\($0)" }).union(["en"])
        #expect(DictationModel.languageFit(codes: many, personLanguages: ["en"], locale: locale)
            == "About 100 languages, including English")
    }
}

/// Option or Command pressed on its own.
@MainActor
@Suite struct ModifierKeyDictationTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_000)
    }

    private func make(
        _ harness: Harness,
        hold: ModifierKey?,
        long: ModifierKey?
    ) throws -> (DictationController, ModifierKeyDictation, Clock) {
        var preferences = AppPreferences()
        preferences.dictationHoldKey = hold
        preferences.dictationLongKey = long
        try harness.settings.setPreferences(preferences)
        let controller = harness.makeDictation()
        let clock = Clock()
        let keys = ModifierKeyDictation(
            controller: controller,
            preferences: { preferences },
            holdDelay: .milliseconds(20),
            now: { clock.now }
        )
        return (controller, keys, clock)
    }

    @Test func holdingTheKeyDictatesUntilItComesUp() async throws {
        let harness = Harness()
        let (controller, keys, clock) = try make(harness, hold: .rightOption, long: nil)

        keys.handle(.down(.rightOption)) { nil }
        #expect(await eventually { controller.phase == .listening })
        #expect(controller.mode == .hold)
        let session = try #require(harness.speech.sessions.last)
        session.willFinish(with: "Held")
        clock.now += 2
        keys.handle(.up(.rightOption)) { nil }
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["Held"])
    }

    @Test func theKeyUsedInAShortcutStartsNothing() async throws {
        let harness = Harness()
        let (controller, keys, clock) = try make(harness, hold: .rightOption, long: .rightOption)

        keys.handle(.down(.rightOption)) { nil }
        keys.handle(.otherKey) { nil }
        clock.now += 0.1
        keys.handle(.up(.rightOption)) { nil }
        try await Task.sleep(for: .milliseconds(60))
        #expect(controller.phase == .idle)
        #expect(harness.speech.sessions.isEmpty)
    }

    @Test func anotherKeyDuringAHoldThrowsTheWordsAway() async throws {
        let harness = Harness()
        let (controller, keys, clock) = try make(harness, hold: .rightOption, long: nil)

        keys.handle(.down(.rightOption)) { nil }
        #expect(await eventually { controller.phase == .listening })
        keys.handle(.otherKey) { nil }
        #expect(controller.phase == .idle)
        clock.now += 1
        keys.handle(.up(.rightOption)) { nil }
        #expect(harness.system.insertCalls.isEmpty)
    }

    @Test func tappingTheLongKeyStartsAndFinishes() async throws {
        let harness = Harness()
        let (controller, keys, clock) = try make(harness, hold: nil, long: .rightCommand)

        keys.handle(.down(.rightCommand)) { nil }
        clock.now += 0.1
        keys.handle(.up(.rightCommand)) { nil }
        #expect(await eventually { controller.phase == .listening })
        #expect(controller.mode == .long)
        let session = try #require(harness.speech.sessions.last)
        session.willFinish(with: "Long one")

        clock.now += 5
        keys.handle(.down(.rightCommand)) { nil }
        clock.now += 0.1
        keys.handle(.up(.rightCommand)) { nil }
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["Long one"])
    }

    @Test func aLongPressOfTheLongKeyIsNotATap() async throws {
        let harness = Harness()
        let (controller, keys, clock) = try make(harness, hold: nil, long: .rightCommand)

        keys.handle(.down(.rightCommand)) { nil }
        clock.now += 1
        keys.handle(.up(.rightCommand)) { nil }
        try await Task.sleep(for: .milliseconds(40))
        #expect(controller.phase == .idle)
    }

    @Test func withOneKeyForBothATapKeepsListeningAndAHoldLetsGo() async throws {
        let harness = Harness()
        let (controller, keys, clock) = try make(harness, hold: .rightOption, long: .rightOption)

        // A tap: the hold starts, then carries on as a long dictation.
        keys.handle(.down(.rightOption)) { nil }
        #expect(await eventually { controller.phase == .listening })
        clock.now += 0.2
        keys.handle(.up(.rightOption)) { nil }
        #expect(controller.mode == .long)
        #expect(controller.phase == .listening)

        // The next tap finishes it.
        let session = try #require(harness.speech.sessions.last)
        session.willFinish(with: "Both")
        clock.now += 3
        keys.handle(.down(.rightOption)) { nil }
        clock.now += 0.1
        keys.handle(.up(.rightOption)) { nil }
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["Both"])
    }

    @Test func intoThePanelFieldWhenThePanelHasTheKeyboard() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        var preferences = AppPreferences()
        preferences.dictationLongKey = .leftOption
        try harness.settings.setPreferences(preferences)
        let controller = harness.makeDictation(panel: panel)
        panel.begin(with: SelectionCapture(app: Harness.slack, text: nil))
        let clock = Clock()
        let keys = ModifierKeyDictation(controller: controller, preferences: { preferences }, now: { clock.now })

        keys.handle(.down(.leftOption)) { .composePrompt }
        clock.now += 0.1
        keys.handle(.up(.leftOption)) { .composePrompt }
        #expect(await eventually { controller.phase == .listening })
        #expect(controller.field == .composePrompt)
        controller.cancel()
    }
}
