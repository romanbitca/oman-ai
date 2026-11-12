import Testing
@testable import OmanUI

@Suite struct TextChangesTests {
    private func original(of changes: TextChanges) -> String {
        changes.pieces.compactMap { piece -> String? in
            if case .added = piece { return nil }
            return piece.text
        }.joined()
    }

    private func corrected(of changes: TextChanges) -> String {
        changes.pieces.compactMap { piece -> String? in
            if case .removed = piece { return nil }
            return piece.text
        }.joined()
    }

    @Test func textThatIsTheSameHasNoChanges() {
        let changes = TextChanges(from: "All good here.", to: "All good here.")
        #expect(changes.pieces == [.same("All good here.")])
        #expect(changes.count == 0)
        #expect(!changes.isRewrite)
    }

    @Test func eachCorrectedWordIsOneChange() {
        let changes = TextChanges(
            from: "sorry for the delay, the invoice was send on monday and you should recieve it untill friday",
            to: "sorry for the delay, the invoice was sent on monday and you should receive it until friday"
        )
        #expect(changes.count == 3)
        #expect(changes.pieces == [
            .same("sorry for the delay, the invoice was "),
            .removed("send"), .added("sent"),
            .same(" on monday and you should "),
            .removed("recieve"), .added("receive"),
            .same(" it "),
            .removed("untill"), .added("until"),
            .same(" friday"),
        ])
        #expect(!changes.isRewrite)
    }

    @Test(arguments: [
        ("hey yes, ill send u the q3 numbers", "hey yes, i'll send u the q3 numbers"),
        ("sorry for the delay the invoice is late", "Sorry for the delay, the invoice is late."),
        ("the the invoice  was sent", "the invoice was sent"),
        ("first line\n\nsecond  line ", "First line.\n\nSecond line"),
        ("", "new text"),
        ("old text", ""),
        ("ok 👍🏽 see u", "OK 👍🏽 see you!"),
        ("Привет, как дила?", "Привет, как дела?"),
    ])
    func thePiecesSpellBothTexts(original: String, corrected: String) {
        let changes = TextChanges(from: original, to: corrected)
        #expect(self.original(of: changes) == original)
        #expect(self.corrected(of: changes) == corrected)
    }

    @Test func anApostropheStaysInsideItsWord() {
        let changes = TextChanges(from: "ill send it, dont worry", to: "i'll send it, don\u{2019}t worry")
        #expect(changes.pieces == [
            .removed("ill"), .added("i'll"),
            .same(" send it, "),
            .removed("dont"), .added("don\u{2019}t"),
            .same(" worry"),
        ])
        #expect(changes.count == 2)
    }

    @Test func anAddedCommaIsAChangeOfItsOwn() {
        let changes = TextChanges(from: "sorry for the delay the invoice is late", to: "sorry for the delay, the invoice is late")
        #expect(changes.pieces == [.same("sorry for the delay"), .added(","), .same(" the invoice is late")])
        #expect(changes.count == 1)
    }

    @Test func aDoubledWordThatWasRemovedIsOneChange() {
        let changes = TextChanges(from: "I sent the the invoice", to: "I sent the invoice")
        #expect(changes.count == 1)
        #expect(changes.pieces.filter { !$0.isSame }.map(\.text).joined().trimmingCharacters(in: .whitespaces) == "the")
    }

    @Test func aCapitalLetterIsAChange() {
        let changes = TextChanges(from: "see you on monday", to: "See you on Monday")
        #expect(changes.count == 2)
        #expect(changes.pieces.first == .removed("see"))
    }

    @Test func spacingAloneIsNotCounted() {
        let changes = TextChanges(from: "one  two\nthree ", to: "one two\nthree")
        #expect(changes.count == 0)
        #expect(changes.pieces.contains { !$0.isSame })
    }

    @Test func wordsNextToEachOtherAreCountedOneByOne() {
        let changes = TextChanges(from: "it was send untill friday", to: "it was sent until friday")
        #expect(changes.count == 2)
    }

    @Test func aTextWrittenAnewIsARewrite() {
        let changes = TextChanges(
            from: "hey yes, ill send u the q3 numbers in a sec, just need to double check the churn figure first",
            to: "Hi Dana, I'm confirming the quarterly report will reach you this afternoon once our finance team signs off."
        )
        #expect(changes.isRewrite)
    }

    @Test func aShortTextIsNeverARewrite() {
        let changes = TextChanges(from: "teh", to: "the")
        #expect(changes.count == 1)
        #expect(!changes.isRewrite)
    }

    @Test func aProofreadOfALongerTextIsNotARewrite() {
        let changes = TextChanges(
            from: "hi anna, thanks for the update. the proposal work for us. could we move the kickoff to thursday? i can do any time after 10.",
            to: "Hi Anna, thanks for the update. The proposal works for us. Could we move the kickoff to Thursday? I can do any time after 10."
        )
        #expect(changes.count == 7)
        #expect(!changes.isRewrite)
    }

    @Test func inJapaneseOnlyTheCorrectedCharacterIsMarked() {
        let changes = TextChanges(from: "明日の会議は三時からです", to: "明日の会議は二時からです")
        #expect(changes.pieces == [.same("明日の会議は"), .removed("三"), .added("二"), .same("時からです")])
        #expect(changes.count == 1)
    }

    @Test func anEmojiIsKeptWhole() {
        let changes = TextChanges(from: "ok 👨‍👩‍👧 see u", to: "ok 👨‍👩‍👧 see you")
        #expect(changes.pieces == [.same("ok 👨‍👩‍👧 see "), .removed("u"), .added("you")])
    }

    @Test func tokensSpellTheTextExactly() {
        let text = "Don't  stop—we're at 3pm (Q3), ok?\n\n«Да» 👍"
        #expect(TextChanges.tokens(of: text).joined() == text)
        #expect(TextChanges.tokens(of: "don't stop").map(String.init) == ["don't", " ", "stop"])
        #expect(TextChanges.tokens(of: "'quoted'").map(String.init) == ["'", "quoted", "'"])
    }
}
