import AppKit
import OmanCore

/// Watches Option and Command pressed on their own, anywhere on the Mac, and any other key pressed while one of
/// them is down. Uses the Accessibility permission OmanAI already has.
@MainActor
final class ModifierKeyMonitor {
    var onEvent: (@MainActor (ModifierKeyEvent) -> Void)?

    private var keys: Set<ModifierKey> = []
    private var down: Set<ModifierKey> = []
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func watch(_ keys: Set<ModifierKey>) {
        self.keys = keys
        if keys.isEmpty {
            stop()
        } else if globalMonitor == nil {
            start()
        }
    }

    private func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        // OmanAI's own windows, such as Settings, get their keys here instead.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    private func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        down.removeAll()
    }

    private func handle(_ event: NSEvent) {
        let watchedDown = !down.intersection(keys).isEmpty
        switch event.type {
        case .flagsChanged:
            let flags = event.modifierFlags
            guard let key = ModifierKey(keyCode: event.keyCode) else {
                // Shift or Control joining in makes it a shortcut, not a key on its own.
                if watchedDown, !flags.intersection([.shift, .control]).isEmpty {
                    onEvent?(.otherKey)
                }
                return
            }
            if Self.isDown(key, flags: flags.rawValue) {
                if watchedDown { onEvent?(.otherKey) }
                down.insert(key)
                // Pressed while another modifier is held, it is part of a shortcut such as ⌘⌥V.
                let alone = !Self.othersDown(besides: key, flags: flags)
                if alone, keys.contains(key) { onEvent?(.down(key)) }
            } else {
                down.remove(key)
                if keys.contains(key) { onEvent?(.up(key)) }
            }
        case .keyDown:
            if watchedDown { onEvent?(.otherKey) }
        default:
            break
        }
    }

    nonisolated static func othersDown(besides key: ModifierKey, flags: NSEvent.ModifierFlags) -> Bool {
        if !flags.intersection([.shift, .control]).isEmpty { return true }
        return ModifierKey.allCases.contains { $0 != key && isDown($0, flags: flags.rawValue) }
    }

    /// The device-dependent bits of the modifier flags tell the left key from the right one.
    nonisolated static func isDown(_ key: ModifierKey, flags: UInt) -> Bool {
        switch key {
        case .leftCommand: flags & 0x08 != 0
        case .rightCommand: flags & 0x10 != 0
        case .leftOption: flags & 0x20 != 0
        case .rightOption: flags & 0x40 != 0
        }
    }
}
