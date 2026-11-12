import OmanCore

/// Sorts what has the cursor into a place that takes text, one that clearly doesn't, or one that can't be told.
/// A wrong "doesn't" would keep dictated words out of an app that could have taken them, so only roles that never
/// take text count as one, and anything unfamiliar can't be told.
enum TextFocusRules {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    static let secureField = "AXSecureTextField"
    /// Controls whose value can be set without being text, such as a slider's or a checkbox's.
    static let controls: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXLink",
        "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXColorWell", "AXScrollBar",
    ]
    /// Where the cursor can rest with nothing to type into: lists, tables, a page with no field in focus, and the
    /// app itself when none of its windows has the keyboard.
    static let places: Set<String> = [
        "AXList", "AXOutline", "AXTable", "AXBrowser", "AXRow", "AXCell", "AXWebArea", "AXApplication",
    ]
    /// The Finder's desktop. It answers with a text range, which finds icons by their names as they are typed.
    static let desktop = "AXDesktop"

    /// The value and the text range are asked for only when the role leaves it open, since every question goes to
    /// another app.
    static func classify(
        role: String?,
        subrole: String?,
        valueIsSettable: @autoclosure () -> Bool,
        hasTextRange: @autoclosure () -> Bool
    ) -> TextFocus {
        // A password field takes a dictation made while it has the cursor, as before, but never words that wait
        // for a click: a click into it is for typing a password, and Return could follow the words.
        if role == secureField || subrole == secureField { return .unknown }
        if let role, textRoles.contains(role) { return .takesText }
        if let subrole, textRoles.contains(subrole) { return .takesText }
        let isControl = role.map(controls.contains) ?? false
        // A text view of an app's own making, or a page made to be written in, such as a mail being composed.
        if !isControl, valueIsSettable() { return .takesText }
        if isControl || subrole == desktop { return .cannotTakeText }
        if let role, places.contains(role) { return .cannotTakeText }
        if hasTextRange() { return .takesText }
        return .unknown
    }
}
