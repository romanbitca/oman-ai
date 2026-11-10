import CoreGraphics

enum KeyEvents {
    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9

    static func postCopy() {
        postCommand(key: keyC)
    }

    static func postPaste() {
        postCommand(key: keyV)
    }

    private static func postCommand(key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
