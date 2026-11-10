import AppKit
import OmanCore
import SwiftUI

/// Without this, a click on a panel that lost focus only refocuses it and the button never fires.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Takes keyboard input without activating oman, so the source app keeps its selection.
final class FloatingPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onKeyCombo: ((KeyCombo) -> Bool)?

    init() {
        // .nonactivatingPanel must be set here: adding it after init does not update the window server.
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        // A window shadow would freeze the outline of glass that is still reshaping.
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    // The panel is key while oman stays inactive, so editing shortcuts can't rely on the main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyCombo?(KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags.rawValue)) == true {
            return true
        }
        if let action = Self.editingAction(for: event), NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static let keysByCode: [UInt16: String] = [0: "a", 6: "z", 7: "x", 8: "c", 9: "v"]

    private static func editingAction(for event: NSEvent) -> Selector? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command || flags == [.command, .shift] else { return nil }

        let typed = event.charactersIgnoringModifiers?.lowercased() ?? ""
        // Cyrillic and other non-Latin layouts report their own letter, so fall back to the physical key.
        let key = typed.allSatisfy(\.isASCII) && !typed.isEmpty ? typed : keysByCode[event.keyCode]

        if flags.contains(.shift) {
            return key == "z" ? Selector(("redo:")) : nil
        }
        switch key {
        case "x": return #selector(NSText.cut(_:))
        case "c": return #selector(NSText.copy(_:))
        case "v": return #selector(NSText.paste(_:))
        case "a": return #selector(NSText.selectAll(_:))
        case "z": return Selector(("undo:"))
        default: return nil
        }
    }
}
