import AppKit
import ApplicationServices
import OmanCore

/// Watches chords of Control, Option and Command keys held on their own, anywhere on the Mac, through
/// `ModifierChordTracker`. Uses the Accessibility permission OmanAI already has.
@MainActor
final class ModifierKeyMonitor {
    var onEvent: (@MainActor (ModifierKeyEvent) -> Void)?

    private var tracker = ModifierChordTracker()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Whether Accessibility was allowed when the monitors were added. Before it is, macOS gives them no keys.
    private var startedTrusted = false

    /// Called again whenever the chords may have changed, or the panel opens, so monitors added before
    /// Accessibility was allowed are added again once it is.
    func watch(_ chords: Set<ModifierChord>) {
        tracker.chords = chords
        if chords.isEmpty {
            stop()
        } else if globalMonitor == nil {
            start()
        } else if !startedTrusted, AXIsProcessTrusted() {
            stop()
            start()
        }
    }

    private func start() {
        startedTrusted = AXIsProcessTrusted()
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
        tracker = ModifierChordTracker(chords: tracker.chords)
    }

    private func handle(_ event: NSEvent) {
        let events: [ModifierKeyEvent]
        switch event.type {
        case .flagsChanged:
            let flags = event.modifierFlags
            events = tracker.flagsChanged(
                held: ModifierKey.down(inDeviceFlags: flags.rawValue),
                othersHeld: !flags.intersection([.shift, .function]).isEmpty
            )
        case .keyDown:
            events = tracker.keyDown()
        default:
            events = []
        }
        for event in events {
            onEvent?(event)
        }
    }
}
