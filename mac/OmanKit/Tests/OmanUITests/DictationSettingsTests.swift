import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

@MainActor
@Suite struct DictationSettingsTests {
    private func loaded(_ harness: Harness) async -> SettingsViewModel {
        let settings = harness.makeSettings()
        settings.reload()
        settings.reloadDictation()
        await settings.dictationTask?.value
        return settings
    }

    @Test func appleIsChosenAtFirstAndListensForTheMacsLanguage() async {
        let harness = Harness()
        let settings = await loaded(harness)

        #expect(settings.preferences.dictationModel == .apple)
        #expect(settings.dictationLanguages.map(\.id) == ["en-US", "ro-RO"])
        #expect(settings.dictationLanguage == DictationLanguage(id: "en-US"))
        #expect(settings.dictationStatus == .ready)
    }

    @Test func eachModelHasItsOwnLanguagesAndChoice() async {
        let harness = Harness()
        let settings = await loaded(harness)

        settings.setDictationModel(.whisper)
        await settings.dictationTask?.value
        #expect(settings.dictationLanguages.first == .automatic)
        #expect(settings.dictationLanguage == .automatic)

        settings.setDictationLanguage(DictationLanguage(id: "ro"))
        await settings.dictationTask?.value
        settings.setDictationModel(.apple)
        await settings.dictationTask?.value
        #expect(settings.dictationLanguage == DictationLanguage(id: "en-US"))

        settings.setDictationModel(.whisper)
        await settings.dictationTask?.value
        #expect(settings.dictationLanguage == DictationLanguage(id: "ro"))
        let saved = try? harness.settings.preferences()
        #expect(saved?.dictationLanguage(for: .whisper) == DictationLanguage(id: "ro"))
        #expect(saved?.dictationModel == .whisper)
    }

    @Test func aModelToDownloadShowsProgressThenIsReady() async {
        let harness = Harness()
        harness.speech.setStatus(.needsDownload(bytes: 626_000_000), for: .parakeet)
        let settings = await loaded(harness)

        settings.setDictationModel(.parakeet)
        await settings.dictationTask?.value
        #expect(settings.dictationStatus == .needsDownload(bytes: 626_000_000))

        settings.downloadModel(.parakeet)
        #expect(settings.downloadProgress == 0)
        #expect(settings.downloadingModel == .parakeet)
        await settings.downloadTask?.value
        await settings.dictationTask?.value
        #expect(settings.downloadProgress == nil)
        #expect(settings.downloadingModel == nil)
        #expect(settings.dictationStatus == .ready)
        #expect(harness.speech.downloads == [.parakeet])
    }

    @Test func aFailedDownloadSaysWhy() async {
        let harness = Harness()
        harness.speech.setStatus(.needsDownload(bytes: nil), for: .whisper)
        harness.speech.failDownload(with: DictationError.failed("The download stopped: offline"))
        let settings = await loaded(harness)
        settings.setDictationModel(.whisper)
        await settings.dictationTask?.value

        settings.downloadModel(.whisper)
        await settings.downloadTask?.value
        #expect(settings.dictationError == "The download stopped: offline")
        #expect(settings.downloadProgress == nil)
    }

    @Test func removingTheChosenDownloadGoesBackToApple() async {
        let harness = Harness()
        let settings = await loaded(harness)
        settings.setDictationModel(.whisper)
        await settings.dictationTask?.value

        settings.removeModel(.whisper)
        #expect(await eventually { harness.speech.removals == [.whisper] })
        #expect(await eventually { settings.preferences.dictationModel == .apple })
        #expect(await eventually { settings.modelStatuses[.whisper] == .needsDownload(bytes: 1_000) })
    }

    @Test func choosingAModelStillToDownloadDownloadsItThenChoosesIt() async {
        let harness = Harness()
        harness.speech.setStatus(.needsDownload(bytes: 609_000_000), for: .parakeetEnglish)
        let settings = await loaded(harness)
        #expect(settings.modelStatuses[.parakeetEnglish] == .needsDownload(bytes: 609_000_000))

        settings.chooseModel(.parakeetEnglish)
        #expect(settings.downloadingModel == .parakeetEnglish)
        #expect(settings.preferences.dictationModel == .apple)
        await settings.downloadTask?.value
        #expect(await eventually { settings.preferences.dictationModel == .parakeetEnglish })
        #expect(await eventually { settings.dictationLanguage == DictationLanguage(id: "en") })
    }

    @Test func eachModelSaysWhichOfThePersonsLanguagesItKnows() async {
        let harness = Harness()
        let settings = await loaded(harness)
        #expect(settings.modelLanguageCodes[.parakeetEnglish] == ["en"])
        #expect(settings.modelLanguageCodes[.nemotron] == ["en", "ro", "ru"])
        #expect(settings.modelLanguageCodes[.apple] == ["en", "ro"])
        #expect(SettingsViewModel.languageCode("ro-RO") == "ro")
        #expect(SettingsViewModel.languageCode("en") == "en")
        #expect(!settings.personLanguages.isEmpty)
    }

    @Test func wordsAreAddedOnceEachAndCanBeRemoved() {
        let harness = Harness()
        let settings = harness.makeSettings()
        settings.reload()

        settings.newDictationWord = "AxiaPOS, Geri ,  "
        settings.addDictationWords()
        settings.newDictationWord = "axiapos"
        settings.addDictationWords()
        #expect(settings.preferences.dictationWords == ["AxiaPOS", "Geri"])
        #expect(settings.newDictationWord.isEmpty)

        settings.removeDictationWord("Geri")
        #expect(settings.preferences.dictationWords == ["AxiaPOS"])
        #expect((try? harness.settings.preferences())?.dictationWords == ["AxiaPOS"])
    }

    @Test func transcriptsCanBeCopiedAndDeleted() async {
        let harness = Harness()
        let older = SavedDictation(date: Date(timeIntervalSince1970: 1), text: "Older", duration: 2, model: "apple", language: "en-US", appName: "Mail")
        let newer = SavedDictation(date: Date(timeIntervalSince1970: 2), text: "Newer", duration: 2, model: "apple", language: "en-US", appName: nil)
        harness.dictations.seed([older, newer])
        let settings = await loaded(harness)
        #expect(settings.savedDictations.map(\.text) == ["Newer", "Older"])

        settings.copyDictation(older)
        #expect(harness.system.copied == ["Older"])
        #expect(settings.copiedDictationID == older.id)

        settings.deleteDictation(id: newer.id)
        #expect(settings.savedDictations.map(\.text) == ["Older"])

        settings.deleteAllDictations()
        #expect(settings.savedDictations.isEmpty)
    }

    @Test func theMicrophoneIsAskedForOnceThenSystemSettingsOpens() async {
        let harness = Harness()
        harness.system.microphoneAccess = .notDetermined
        let settings = await loaded(harness)
        #expect(settings.microphoneAccess == .notDetermined)

        settings.allowMicrophone()
        #expect(await eventually { settings.microphoneAccess == .granted })
        #expect(harness.system.microphoneRequests == 1)

        harness.system.microphoneAccess = .denied
        settings.allowMicrophone()
        #expect(harness.system.microphoneSettingsOpened == 1)
    }

    @Test func dictationShortcutsAreSavedAndRegisteredAnywhere() {
        let harness = Harness()
        let settings = harness.makeSettings()
        settings.reload()
        let combo = KeyCombo(keyCode: 49, modifiers: KeyCombo.option)

        settings.startRecording(.dictateHold)
        settings.finishRecording(with: combo)

        #expect(harness.system.registered[.dictateHold] == combo)
        #expect(!settings.globalShortcutActions.contains(.dictateHold))
        let saved = try? harness.settings.preferences()
        #expect(saved?.combo(for: .dictateHold) == combo)
    }

    @Test func dictationPreferencesSurviveAndOldOnesStillLoad() throws {
        var preferences = AppPreferences()
        preferences.dictationModel = .parakeet
        preferences.dictationPillPosition = .bottom
        preferences.dictationPillStyle = .floating
        preferences.keepsDictations = false
        preferences.dictationWords = ["AxiaPOS"]
        preferences.removesFillerWords = false
        preferences.modelUnloadDelay = .never
        preferences.setDictationLanguage(DictationLanguage(id: "ro"), for: .whisper)
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(AppPreferences.self, from: data) == preferences)

        let old = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"keepsPanelOpen":true}"#.utf8))
        #expect(old.dictationModel == .apple)
        #expect(old.dictationPillPosition == .menuBar)
        #expect(old.dictationPillStyle == .card)
        #expect(old.dictationWords.isEmpty)
        #expect(old.removesFillerWords)
        #expect(old.modelUnloadDelay == .fiveMinutes)
        #expect(old.keepsDictations)
        #expect(old.dictationLanguages.isEmpty)
    }

    @Test func dictationShortcutsHaveStorageKeys() {
        for action in ShortcutAction.dictationActions {
            #expect(ShortcutAction(storageKey: action.storageKey) == action)
            #expect(action.isGlobal)
            #expect(action.isDictation)
        }
        #expect(ShortcutAction(storageKey: ShortcutAction.cancelDictation.storageKey) == nil)
    }
}

@Suite struct DictationPillTests {
    @Test func shortWordsShowWhole() {
        let words = PillWords(LiveTranscript(confirmed: "Hello there", tentative: "how are"), limit: 150)
        #expect(words.settled == "Hello there")
        #expect(words.tentative == " how are")
    }

    @Test func longWordsShowTheirEndFromAWholeWord() {
        let confirmed = (1...60).map { "word\($0)" }.joined(separator: " ")
        let words = PillWords(LiveTranscript(confirmed: confirmed, tentative: "last guess"), limit: 40)
        let shown = words.settled + words.tentative
        #expect(shown.hasPrefix("…word"))
        #expect(shown.hasSuffix("word60 last guess"))
        #expect(words.tentative == " last guess")
        #expect(shown.count <= 41)
    }

    @Test func aGuessAloneIsAllTentative() {
        let words = PillWords(LiveTranscript(confirmed: "", tentative: "maybe this"), limit: 150)
        #expect(words.settled.isEmpty)
        #expect(words.tentative == "maybe this")
    }

    @Test func theWaveFollowsTheVoiceButNeverGoesFlat() {
        #expect(DictationWave.amplitude(forLevel: 0) > 0.1)
        #expect(DictationWave.amplitude(forLevel: 1) == 1)
        #expect(DictationWave.amplitude(forLevel: 2) == 1)
        #expect(DictationWave.amplitude(forLevel: 0.5) > DictationWave.amplitude(forLevel: 0.2))
    }

    @Test func theSecondsCountMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(DictationPillView.elapsed(from: nil, to: start) == "0:00")
        #expect(DictationPillView.elapsed(from: start, to: start.addingTimeInterval(7.9)) == "0:07")
        #expect(DictationPillView.elapsed(from: start, to: start.addingTimeInterval(65)) == "1:05")
        #expect(DictationPillView.elapsed(from: start, to: start.addingTimeInterval(-3)) == "0:00")
    }

    @Test func theFloatingBlurIsFullInTheMiddleAndGoneAtTheEdge() {
        #expect(SoftBlurView.strength(atDistance: 0) == 1)
        #expect(SoftBlurView.strength(atDistance: 0.5) == 1)
        #expect(SoftBlurView.strength(atDistance: 1) == 0)
        #expect(SoftBlurView.strength(atDistance: 0.75) > 0.3)
        #expect(SoftBlurView.strength(atDistance: 0.75) < 0.7)
        let image = SoftBlurView.feather(size: CGSize(width: 100, height: 40))
        #expect(image?.width == 50)
        #expect(image?.height == 20)
    }

    @Test func joiningSpeechLeavesOneSpace() {
        #expect(LiveTranscript.join(" Hello ", " world ") == "Hello world")
        #expect(LiveTranscript.join("", "world") == "world")
        #expect(LiveTranscript.join("Hello", "") == "Hello")
    }
}
