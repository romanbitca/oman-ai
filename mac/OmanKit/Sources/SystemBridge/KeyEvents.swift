import CoreGraphics

enum KeyEvents {
    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9
    private static let keyReturn: CGKeyCode = 36

    static func postCopy() {
        postCommand(key: keyC)
    }

    static func postPaste() {
        postCommand(key: keyV)
    }

    static func postReturn(command: Bool) {
        post(key: keyReturn, flags: command ? .maskCommand : [])
    }

    private static func postCommand(key: CGKeyCode) {
        post(key: key, flags: .maskCommand)
    }

    private static func post(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
