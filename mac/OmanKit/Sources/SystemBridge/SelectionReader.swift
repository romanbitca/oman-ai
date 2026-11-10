import ApplicationServices

enum AccessibilityReading: Equatable {
    case secure
    case selected(String)
    case noSelection
    case unavailable

    private static let secureTextField = "AXSecureTextField"

    static func isSecure(role: String?, subrole: String?) -> Bool {
        role == secureTextField || subrole == secureTextField
    }

    static func classify(selectedText: String?, selectedRangeLength: Int?) -> AccessibilityReading {
        if let selectedText, !selectedText.isEmpty {
            return .selected(selectedText)
        }
        if selectedRangeLength == 0 {
            return .noSelection
        }
        return .unavailable
    }
}

enum SelectionReader {
    // The default is six seconds, which would freeze the menu bar click on a hung app.
    private static let messagingTimeoutSeconds: Float = 0.25

    /// Nil when the app doesn't say what has keyboard focus, as Electron apps don't.
    static func focusedElement(processID: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, messagingTimeoutSeconds)
        guard let focused = element(of: application, attribute: "AXFocusedUIElement") else {
            return nil
        }
        AXUIElementSetMessagingTimeout(focused, messagingTimeoutSeconds)
        return focused
    }

    static func read(_ focused: AXUIElement?) -> AccessibilityReading {
        guard let focused else { return .unavailable }

        if AccessibilityReading.isSecure(
            role: string(of: focused, attribute: "AXRole"),
            subrole: string(of: focused, attribute: "AXSubrole")
        ) {
            return .secure
        }
        return AccessibilityReading.classify(
            selectedText: string(of: focused, attribute: "AXSelectedText"),
            selectedRangeLength: rangeLength(of: focused, attribute: "AXSelectedTextRange")
        )
    }

    private static func value(of element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func string(of element: AXUIElement, attribute: String) -> String? {
        value(of: element, attribute: attribute) as? String
    }

    private static func element(of parent: AXUIElement, attribute: String) -> AXUIElement? {
        guard let value = value(of: parent, attribute: attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        // CoreFoundation types cannot be checked with as?; the type ID was verified above.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func rangeLength(of element: AXUIElement, attribute: String) -> Int? {
        guard let value = value(of: element, attribute: attribute),
              CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        // CoreFoundation types cannot be checked with as?; the type ID was verified above.
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range.length
    }
}
