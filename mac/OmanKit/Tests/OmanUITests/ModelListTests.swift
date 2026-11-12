import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

/// What the list of dictation models says about each one.
@Suite struct ModelListTests {
    @Test func everyModelHasItsFacts() {
        for model in DictationModel.allCases {
            #expect((1...5).contains(model.speed), "\(model) speed")
            #expect((1...5).contains(model.accuracy), "\(model) accuracy")
            #expect(!model.maker.isEmpty)
            #expect(!model.license.isEmpty)
            #expect(!model.languageChoice.isEmpty)
            #expect(!model.sizeText.isEmpty)
        }
        #expect(DictationModel.apple.sizeText == "Built in")
    }

    @Test func theLiveModelsAreFastestAndReadingAgainIsMoreAccurate() {
        // The live models are the fastest; reading again is what makes the others accurate.
        let live = DictationModel.allCases.filter(\.isLive)
        let others = DictationModel.allCases.filter { !$0.isLive }
        #expect(live.allSatisfy { $0.speed >= 4 })
        #expect(others.allSatisfy { $0.speed <= 3 })
        #expect(DictationModel.whisperLarge.accuracy > DictationModel.whisperSmall.accuracy)
        #expect(DictationModel.whisperLarge.speed < DictationModel.whisper.speed)
    }

    @Test func eachLevelHasAWordAndAMeaning() {
        let speeds = (1...5).map(DictationModel.speedWord)
        let accuracies = (1...5).map(DictationModel.accuracyWord)
        #expect(Set(speeds).count == 5)
        #expect(Set(accuracies).count == 5)
        #expect(DictationModel.speedWord(5) == "Instant")
        #expect(DictationModel.accuracyWord(5) == "Excellent")
        #expect(Set((1...5).map(DictationModel.speedMeaning)).count == 5)
        #expect(Set((1...5).map(DictationModel.accuracyMeaning)).count == 5)
    }

    @Test func languagesAreCountedInWords() {
        #expect(DictationModel.languageCount(["en"]).hasSuffix(" only"))
        #expect(DictationModel.languageCount(Set((0..<25).map { "x\($0)" })) == "25 languages")
        #expect(DictationModel.languageCount(Set((0..<99).map { "x\($0)" })) == "About 100 languages")
    }

    @Test func theSuggestionIsTheFastestLiveModelThatKnowsEveryOneOfYourLanguages() {
        let knows: [DictationModel: Set<String>] = [
            .parakeetEnglish: ["en"],
            .nemotron: ["en", "ro", "ru", "fr"],
            .apple: ["en", "ro", "ja"],
            .whisper: ["en", "ro", "ru", "ja", "ko"],
        ]
        #expect(DictationModel.suggested(for: ["en"], knows: knows, unavailable: []) == .parakeetEnglish)
        #expect(DictationModel.suggested(for: ["en", "ru", "ro"], knows: knows, unavailable: []) == .nemotron)
        #expect(DictationModel.suggested(for: ["en", "ja"], knows: knows, unavailable: []) == .apple)
        // Only live models are suggested, and only ones that can run here.
        #expect(DictationModel.suggested(for: ["ko"], knows: knows, unavailable: []) == nil)
        #expect(DictationModel.suggested(for: ["en", "ja"], knows: knows, unavailable: [.apple]) == nil)
        #expect(DictationModel.suggested(for: [], knows: knows, unavailable: []) == nil)
    }
}
