import Testing
@testable import OmanUI

@Suite struct ResultCleanerTests {
    @Test func ordinaryTextIsUntouched() {
        let text = "Привет, мир 👋 — see https://a.b/c?x=1&y=2\n\nSecond paragraph."
        #expect(ResultCleaner.clean(text, source: nil) == .init(text: text, removedHiddenCharacters: false))
    }

    @Test func invisibleTagCharactersAreRemoved() {
        // Tag characters are invisible copies of ASCII; these spell "hi".
        let cleaned = ResultCleaner.clean("Sure\u{E0068}\u{E0069}.", source: "anything")
        #expect(cleaned == .init(text: "Sure.", removedHiddenCharacters: true))
    }

    @Test func tagCharactersAreRemovedEvenIfTheSourceHadThem() {
        let cleaned = ResultCleaner.clean("ok\u{E0041}", source: "source\u{E0041}")
        #expect(cleaned == .init(text: "ok", removedHiddenCharacters: true))
    }

    @Test func flagsBuiltFromTagCharactersSurvive() {
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        let text = "Off to \(scotland) tomorrow"
        #expect(ResultCleaner.clean(text, source: nil) == .init(text: text, removedHiddenCharacters: false))
    }

    @Test func emojiJoinersAndDirectionMarksSurvive() {
        // A family emoji needs zero-width joiners, and right-to-left text uses direction marks.
        let text = "👨‍👩‍👧 שלום\u{200F} می‌خواهم"
        #expect(ResultCleaner.clean(text, source: nil) == .init(text: text, removedHiddenCharacters: false))
    }

    @Test(arguments: ["\u{200B}", "\u{2060}", "\u{FEFF}", "\u{00AD}", "\u{202E}", "\u{2066}", "\u{2069}"])
    func hiddenControlsTheSourceDidNotHaveAreRemoved(hidden: String) {
        let cleaned = ResultCleaner.clean("pay\(hidden)ment", source: "payment")
        #expect(cleaned == .init(text: "payment", removedHiddenCharacters: true))
    }

    @Test func hiddenControlsTheSourceAlreadyHadAreKept() {
        let text = "soft\u{00AD}hyphen and \u{202B}embedded\u{202C} text"
        #expect(ResultCleaner.clean(text, source: text) == .init(text: text, removedHiddenCharacters: false))
    }

    @Test func newTextNeverKeepsHiddenControls() {
        let cleaned = ResultCleaner.clean("a\u{200B}b", source: nil)
        #expect(cleaned == .init(text: "ab", removedHiddenCharacters: true))
    }

    @Test func trailingLineBreaksAreTrimmedWithoutANotice() {
        #expect(ResultCleaner.clean("ls -la\n\r\n", source: "ls") == .init(text: "ls -la", removedHiddenCharacters: false))
        #expect(ResultCleaner.clean("Thanks!\n", source: nil) == .init(text: "Thanks!", removedHiddenCharacters: false))
    }

    @Test func aLineBreakThePersonEndedWithIsKept() {
        let cleaned = ResultCleaner.clean("First line.\n", source: "first line\n")
        #expect(cleaned == .init(text: "First line.\n", removedHiddenCharacters: false))
    }

    @Test func lineBreaksInsideTheTextAreKept() {
        let text = "One\n\nTwo\nThree"
        #expect(ResultCleaner.clean(text, source: nil).text == text)
    }
}
