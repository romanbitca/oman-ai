import Carbon.HIToolbox
import OmanCore

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let identifier = hotKeyID.id
    let isRelease = GetEventKind(event) == UInt32(kEventHotKeyReleased)
    let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
    // Carbon delivers hot key events on the main run loop.
    MainActor.assumeIsolated { hotKeys.fire(identifier: identifier, isRelease: isRelease) }
    return noErr
}

@MainActor
final class GlobalHotKeys {
    // "oman" as a four-character code.
    private static let signature: OSType = 0x6F6D_616E

    var onTrigger: (@MainActor (ShortcutAction) -> Void)?
    /// Called when the keys are let go, for a shortcut that is held down while the person speaks.
    var onRelease: (@MainActor (ShortcutAction) -> Void)?

    private var registered: [UInt32: (reference: EventHotKeyRef, action: ShortcutAction)] = [:]
    /// Taken beside the registered shortcuts for a while, such as Escape during a dictation. Their identifiers
    /// start far above the registered ones, which count up from 1.
    private var temporary: [UInt32: (reference: EventHotKeyRef, action: ShortcutAction)] = [:]
    private var nextTemporaryIdentifier: UInt32 = 10_000
    private var handler: EventHandlerRef?

    func register(_ shortcuts: [ShortcutAction: KeyCombo]) -> Set<ShortcutAction> {
        unregisterAll()
        installHandlerIfNeeded()

        var failures = Set<ShortcutAction>()
        var identifier: UInt32 = 1
        for (action, combo) in shortcuts {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(combo.keyCode),
                Self.carbonModifiers(from: combo.modifiers),
                EventHotKeyID(signature: Self.signature, id: identifier),
                GetEventDispatcherTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                registered[identifier] = (reference, action)
            } else {
                failures.insert(action)
            }
            identifier += 1
        }
        return failures
    }

    func unregisterAll() {
        for entry in registered.values {
            UnregisterEventHotKey(entry.reference)
        }
        registered.removeAll()
    }

    /// Adds one shortcut beside the registered ones without touching them, or takes it away again with nil.
    /// Registering everything again would lose the release of a shortcut that is being held down.
    /// Returns false when the combination could not be taken.
    @discardableResult
    func setTemporary(_ combo: KeyCombo?, for action: ShortcutAction) -> Bool {
        if let entry = temporary.first(where: { $0.value.action == action }) {
            UnregisterEventHotKey(entry.value.reference)
            temporary[entry.key] = nil
        }
        guard let combo else { return true }
        installHandlerIfNeeded()
        let identifier = nextTemporaryIdentifier
        nextTemporaryIdentifier += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            Self.carbonModifiers(from: combo.modifiers),
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        temporary[identifier] = (reference, action)
        return true
    }

    func fire(identifier: UInt32, isRelease: Bool) {
        guard let action = registered[identifier]?.action ?? temporary[identifier]?.action else { return }
        if isRelease {
            onRelease?(action)
        } else {
            onTrigger?(action)
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    nonisolated static func carbonModifiers(from modifiers: UInt) -> UInt32 {
        var result = 0
        if modifiers & KeyCombo.command != 0 { result |= cmdKey }
        if modifiers & KeyCombo.option != 0 { result |= optionKey }
        if modifiers & KeyCombo.control != 0 { result |= controlKey }
        if modifiers & KeyCombo.shift != 0 { result |= shiftKey }
        return UInt32(result)
    }
}
