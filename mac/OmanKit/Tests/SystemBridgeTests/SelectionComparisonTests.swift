import Testing
@testable import SystemBridge

@Suite struct SelectionComparisonTests {
    @Test(arguments: [
        ("one\r\ntwo", "one\ntwo"),
        ("one\rtwo", "one\ntwo"),
        ("hello\u{00A0}there", "hello there"),
        ("  hello\n", "hello"),
        ("\u{00A0}hello\u{00A0}", "hello"),
        ("Привет, как дела?", "Привет, как дела?"),
    ])
    func treatsAsSame(lhs: String, rhs: String) {
        #expect(SelectionComparison.matches(lhs, rhs))
    }

    @Test(arguments: [
        ("hello", "hello there"),
        ("hello", "Hello"),
        ("one  two", "one two"),
        ("one\n\ntwo", "one\ntwo"),
        ("", "hello"),
    ])
    func treatsAsDifferent(lhs: String, rhs: String) {
        #expect(!SelectionComparison.matches(lhs, rhs))
    }

    @Test func nonBlankRejectsNilAndWhitespace() {
        #expect(SelectionComparison.nonBlank(nil) == nil)
        #expect(SelectionComparison.nonBlank("") == nil)
        #expect(SelectionComparison.nonBlank(" \n\t\u{00A0}") == nil)
    }

    @Test func nonBlankKeepsSurroundingWhitespace() {
        #expect(SelectionComparison.nonBlank("  hello\n") == "  hello\n")
    }
}
