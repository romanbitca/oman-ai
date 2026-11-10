import Testing
@testable import SystemBridge

@Suite struct AccessibilityReadingTests {
    @Test func secureRoleAndSubroleAreSecure() {
        #expect(AccessibilityReading.isSecure(role: "AXSecureTextField", subrole: nil))
        #expect(AccessibilityReading.isSecure(role: "AXTextField", subrole: "AXSecureTextField"))
    }

    @Test func ordinaryFieldsAreNotSecure() {
        #expect(!AccessibilityReading.isSecure(role: "AXTextField", subrole: nil))
        #expect(!AccessibilityReading.isSecure(role: "AXTextArea", subrole: "AXSearchField"))
        #expect(!AccessibilityReading.isSecure(role: nil, subrole: nil))
    }

    @Test func nonEmptyTextIsSelected() {
        #expect(AccessibilityReading.classify(selectedText: "hello", selectedRangeLength: 5) == .selected("hello"))
        #expect(AccessibilityReading.classify(selectedText: "hello", selectedRangeLength: nil) == .selected("hello"))
    }

    @Test func zeroLengthRangeIsTrustedAsNoSelection() {
        #expect(AccessibilityReading.classify(selectedText: "", selectedRangeLength: 0) == .noSelection)
        #expect(AccessibilityReading.classify(selectedText: nil, selectedRangeLength: 0) == .noSelection)
    }

    @Test func unreadableSelectionIsUnavailable() {
        #expect(AccessibilityReading.classify(selectedText: nil, selectedRangeLength: 12) == .unavailable)
        #expect(AccessibilityReading.classify(selectedText: "", selectedRangeLength: 12) == .unavailable)
    }

    @Test func unsupportedAttributesAreUnavailable() {
        #expect(AccessibilityReading.classify(selectedText: nil, selectedRangeLength: nil) == .unavailable)
        #expect(AccessibilityReading.classify(selectedText: "", selectedRangeLength: nil) == .unavailable)
    }
}
