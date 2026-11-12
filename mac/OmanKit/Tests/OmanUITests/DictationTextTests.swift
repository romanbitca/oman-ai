import Testing
@testable import OmanCore

@Suite struct DictationTextTests {
    @Test(arguments: [
        ("Um, I think so.", "I think so."),
        ("I think, uh, we should go", "I think, we should go"),
        ("We should go uh.", "We should go."),
        ("The umbrella and the errand stay", "The umbrella and the errand stay"),
        ("Ну э давай", "Ну давай"),
        ("Hmm", ""),
    ])
    func fillersAreTakenOutWhereTheyStandAlone(heard: String, expected: String) {
        #expect(DictationText.removingFillers(from: heard) == expected)
    }

    @Test(arguments: [
        ("The axia pos release", ["AxiaPOS"], "The AxiaPOS release"),
        ("Open Axia OS now", ["AxiaOS"], "Open AxiaOS now"),
        ("We shipped axiapose today.", ["AxiaPOS"], "We shipped AxiaPOS today."),
        ("Ask Geri, then Gary", ["Geri"], "Ask Geri, then Gary"),
        ("Axia. Pos is a word", ["AxiaPOS"], "Axia. Pos is a word"),
        ("Thanks to claude code", ["Claude Code"], "Thanks to Claude Code"),
        ("Nothing to change", [], "Nothing to change"),
    ])
    func theChosenWordsAreSpelledTheirWay(heard: String, words: [String], expected: String) {
        #expect(DictationText.applying(words, to: heard) == expected)
    }

    @Test func similarityCountsTheLettersThatMustChange() {
        #expect(DictationText.similarity("axiapos", "axiapos") == 1)
        #expect(DictationText.similarity("axiapose", "axiapos") > 0.8)
        #expect(DictationText.similarity("gary", "geri") < 0.8)
    }

    @Test func modelsDescribeThemselves() {
        #expect(DictationModel.allCases.filter(\.isLive) == [.apple, .parakeetEnglish, .nemotron])
        #expect(DictationModel.apple.downloadSize == nil)
        #expect(DictationModel.allCases.filter(\.isDownloaded).allSatisfy { $0.downloadSize != nil })
        #expect(DictationModel(rawValue: "parakeet-v3") == .parakeet)
        #expect(ModelUnloadDelay.never.seconds == nil)
        #expect(ModelUnloadDelay.fiveMinutes.seconds == 300)
    }
}
