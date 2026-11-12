import OmanCore
import Testing
@testable import SystemBridge

@Suite struct TextFocusRulesTests {
    private func focus(_ role: String?, _ subrole: String? = nil, settable: Bool = false, range: Bool = false) -> TextFocus {
        TextFocusRules.classify(role: role, subrole: subrole, valueIsSettable: settable, hasTextRange: range)
    }

    @Test(arguments: ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"])
    func fieldsTakeText(role: String) {
        #expect(focus(role) == .takesText)
        #expect(focus(role, settable: true, range: true) == .takesText)
    }

    @Test func aSearchFieldIsKnownByItsSubroleToo() {
        #expect(focus("AXTextField", "AXSearchField") == .takesText)
        #expect(focus(nil, "AXSearchField") == .takesText)
    }

    @Test func aTerminalsTextTakesAPasteThoughItsValueCantBeSet() {
        // Terminal shows its text as a text area whose value can't be set, and a paste still goes in.
        #expect(focus("AXTextArea", settable: false, range: true) == .takesText)
    }

    @Test func aViewOfAnAppsOwnMakingTakesTextWhenItsValueCanBeSet() {
        #expect(focus("AXGroup", settable: true) == .takesText)
        #expect(focus("AXScrollArea", settable: true) == .takesText)
    }

    @Test func aPageMadeToBeWrittenInTakesText() {
        // A mail being composed is an editable page, whose value can be set.
        #expect(focus("AXWebArea", settable: true) == .takesText)
    }

    @Test func theDesktopTakesNoTextThoughItHasATextRange() {
        // As the Finder answered on macOS 27.
        #expect(focus("AXGroup", "AXDesktop", settable: false, range: true) == .cannotTakeText)
    }

    @Test(arguments: ["AXList", "AXOutline", "AXTable", "AXBrowser", "AXRow", "AXCell", "AXWebArea", "AXApplication"])
    func listsTablesPagesAndTheAppItselfTakeNoText(role: String) {
        #expect(focus(role) == .cannotTakeText)
        // A list finds a row by its name as it is typed, and is still no field.
        #expect(focus(role, range: true) == .cannotTakeText)
    }

    @Test(arguments: ["AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXSlider", "AXLink"])
    func controlsTakeNoTextEvenWithAValueThatCanBeSet(role: String) {
        #expect(focus(role) == .cannotTakeText)
        #expect(focus(role, settable: true, range: true) == .cannotTakeText)
    }

    @Test func aPasswordFieldIsNeverSure() {
        #expect(focus("AXTextField", "AXSecureTextField", settable: true, range: true) == .unknown)
        #expect(focus("AXSecureTextField") == .unknown)
    }

    @Test func somethingUnfamiliarCantBeTold() {
        #expect(focus("AXGroup") == .unknown)
        #expect(focus("AXWindow") == .unknown)
        #expect(focus("AXScrollArea") == .unknown)
        #expect(focus(nil) == .unknown)
    }

    @Test func somethingUnfamiliarWithATextRangeTakesText() {
        #expect(focus("AXGroup", range: true) == .takesText)
        #expect(focus("AXUnknown", range: true) == .takesText)
    }

    @Test func theValueAndTheRangeAreOnlyAskedForWhenTheRoleLeavesItOpen() {
        var asked: [String] = []
        func settable() -> Bool {
            asked.append("value")
            return false
        }
        func range() -> Bool {
            asked.append("range")
            return false
        }
        _ = TextFocusRules.classify(role: "AXTextArea", subrole: nil, valueIsSettable: settable(), hasTextRange: range())
        _ = TextFocusRules.classify(role: "AXButton", subrole: nil, valueIsSettable: settable(), hasTextRange: range())
        #expect(asked.isEmpty)
        _ = TextFocusRules.classify(role: "AXList", subrole: nil, valueIsSettable: settable(), hasTextRange: range())
        #expect(asked == ["value"])
        _ = TextFocusRules.classify(role: "AXGroup", subrole: nil, valueIsSettable: settable(), hasTextRange: range())
        #expect(asked == ["value", "value", "range"])
    }

    @Test func anAppThatDoesNotAnswerCantBeTold() {
        // No such process: there is nobody to answer.
        #expect(SelectionReader.textFocus(processID: Int32.max) == .unknown)
    }

    @Test func accessibilitySupportIsOnlySwitchedOnWhereItReadsAsOff() {
        // No such process, so the switch can't be read, and nothing is switched on.
        #expect(!SelectionReader.switchOnManualAccessibility(processID: Int32.max))
    }
}
