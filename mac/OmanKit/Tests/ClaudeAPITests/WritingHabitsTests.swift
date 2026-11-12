import Testing

@testable import ClaudeAPI

struct WritingHabitsTests {
    private let chat = [
        "yo, pushed the fix. can you take a look when you get a sec?",
        "nah that's fine, we can ship it tomorrow",
        "hmm not sure tbh, lemme check and get back to you",
        "ok cool, thx!",
        "sounds good, i'll ping you after lunch",
    ]

    private let emails = [
        "Hi Anna,\n\nThanks for the update. I had a look at the proposal and it works for us.\n\nBest,\nSam",
        "Hello team,\n\nThe release is planned for next Tuesday. Please finish your reviews by Monday evening.\n\nThanks,\nSam",
    ]

    @Test func chatMessagesShowLowerCaseApostrophesAndNoFinalFullStop() {
        let habits = WritingHabits(of: chat)
        #expect(habits.startsSentencesInLowerCase == true)
        #expect(habits.leavesOutFinalFullStop)
        #expect(habits.apostrophes == .written)
    }

    @Test func emailsShowCapitalsAndSayNothingAboutHowAMessageEnds() {
        let habits = WritingHabits(of: emails)
        #expect(habits.startsSentencesInLowerCase == false)
        // They end with a name, not a sentence, so they are not counted.
        #expect(!habits.leavesOutFinalFullStop)
    }

    @Test func oneLineMessagesThatEndWithAFullStopKeepIt() {
        let habits = WritingHabits(of: ["Sounds good.", "I will send it today.", "See you there"])
        #expect(!habits.leavesOutFinalFullStop)
    }

    @Test func aQuestionOrExclamationSaysNothingAboutFullStops() {
        #expect(!WritingHabits(of: ["Are you coming?", "Great!"]).leavesOutFinalFullStop)
        #expect(WritingHabits(of: ["Are you coming?", "Great!", "see you there"]).leavesOutFinalFullStop)
    }

    @Test func englishContractionsWithoutApostrophesCountAsLeftOut() {
        let habits = WritingHabits(of: ["cant talk rn, call u later", "dont worry about it", "im on my way", "thats what i said lol"])
        #expect(habits.apostrophes == .leftOut)
        #expect(habits.startsSentencesInLowerCase == true)
    }

    @Test func oneWrittenApostropheOutweighsBareContractions() {
        #expect(WritingHabits(of: ["dont worry about it", "that\u{2019}s what i said"]).apostrophes == .written)
    }

    @Test func messagesWithoutContractionsLeaveApostrophesUnknown() {
        #expect(WritingHabits(of: ["See you at the office tomorrow morning.", "The report is ready for review."]).apostrophes == .unknown)
    }

    @Test func aBareContractionInAnotherLanguageIsNotEvidence() {
        // "im" is an ordinary German word.
        let habits = WritingHabits(of: ["Ich bin gerade im Büro und komme später nach Hause.", "Wir sehen uns morgen im Besprechungsraum."])
        #expect(habits.apostrophes == .unknown)
    }

    @Test func aFullStopInsideAWordStartsNoSentence() {
        // Counted as one capital start; "com", "5" and "is" open nothing.
        let habits = WritingHabits(of: ["See example.com for version 3.5 which is out"])
        #expect(habits.startsSentencesInLowerCase == false)
    }

    @Test func eachLineAndEachSentenceCounts() {
        #expect(WritingHabits(of: ["hi team,\n\nquick update: the release is late.\n- api is done\n- ui still needs work"]).startsSentencesInLowerCase == true)
        #expect(WritingHabits(of: ["Hi Anna. I had a look. could we move it?"]).startsSentencesInLowerCase == false)
    }

    @Test func aSmallIInsideASentenceCountsAsLowerCase() {
        // One capital start against two small i's.
        #expect(WritingHabits(of: ["Hey can u send it, i need it today and i'm late"]).startsSentencesInLowerCase == true)
        #expect(WritingHabits(of: ["Hey can u send it, I need it today"]).startsSentencesInLowerCase == false)
    }

    @Test func aTieCountsAsFormal() {
        #expect(WritingHabits(of: ["Hello there. sorry for the delay"]).startsSentencesInLowerCase == false)
    }

    @Test func textWithoutCapitalLettersToCountSaysNothing() {
        #expect(WritingHabits(of: ["你好，明天见。", "12 34"]).startsSentencesInLowerCase == nil)
        #expect(WritingHabits(of: []).startsSentencesInLowerCase == nil)
    }

    @Test func aSentenceThatOpensWithANumberIsSkipped() {
        #expect(WritingHabits(of: ["3 files changed. All good."]).startsSentencesInLowerCase == false)
        #expect(WritingHabits(of: ["3 files changed. all good"]).startsSentencesInLowerCase == true)
    }

    @Test func quotesAndEmojiBeforeTheFirstLetterAreSkipped() {
        #expect(WritingHabits(of: ["\"sure\" was all he said", "👋 hey there"]).startsSentencesInLowerCase == true)
    }
}

struct TextLanguageTests {
    @Test(arguments: [
        ("Can you send me the report by Friday? I need it for the board meeting.", "en", "English"),
        ("Vezi că mâine nu mai pot veni la ședință, a apărut ceva.", "ro", "Romanian"),
        ("Passt schon. Mach einfach, wie du denkst.", "de", "German"),
        ("Привет, можешь прислать отчёт до пятницы?", "ru", "Russian"),
    ])
    func tellsTheLanguageOfASentence(text: String, code: String, name: String) {
        #expect(TextLanguage.code(of: text) == code)
        #expect(TextLanguage.name(of: text) == name)
    }

    @Test func saysNothingAboutTextTooShortToTell() {
        #expect(TextLanguage.code(of: "ok") == nil)
        #expect(TextLanguage.name(of: "") == nil)
        #expect(TextLanguage.name(of: "12:30") == nil)
    }
}
