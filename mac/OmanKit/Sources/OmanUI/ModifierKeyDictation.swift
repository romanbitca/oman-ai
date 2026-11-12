import Foundation
import OmanCore

/// Turns chords of Control, Option or Command keys held on their own into dictation, such as Right ⌥ alone or
/// Right ⌥ with Right ⌘. Holding the hold chord dictates while it is down; a tap on the long chord starts a long
/// dictation, and another tap finishes it. With the same chord for both, a tap starts a long dictation and holding
/// it dictates until it comes up. Keys used with another, as in ⌥E for é, stay an ordinary shortcut: nothing
/// starts, or a dictation they started is dropped.
@MainActor
public final class ModifierKeyDictation {
    /// A press shorter than this is a tap.
    static let tapLimit: TimeInterval = 0.35

    private let controller: DictationController
    private let preferences: () -> AppPreferences
    private let now: () -> Date
    /// A hold dictation starts this long after the chord goes down, so a quick ⌥E never starts one.
    private let holdDelay: Duration
    private var pressed: ModifierChord?
    private var pressedAt = Date.distantPast
    private var usedWithOtherKey = false
    private var startedHold = false
    private var holdTask: Task<Void, Never>?

    public init(
        controller: DictationController,
        preferences: @escaping () -> AppPreferences,
        holdDelay: Duration = .milliseconds(150),
        now: @escaping () -> Date = Date.init
    ) {
        self.controller = controller
        self.preferences = preferences
        self.holdDelay = holdDelay
        self.now = now
    }

    /// `panelField` is where the words go when the panel holds the keyboard, as for the other shortcuts.
    public func handle(_ event: ModifierKeyEvent, panelField: @escaping () -> PanelField?) {
        switch event {
        case .down(let chord):
            pressed = chord
            pressedAt = now()
            usedWithOtherKey = false
            startedHold = false
            holdTask?.cancel()
            guard chord == preferences().dictationHoldKey, !controller.isActive else { return }
            let delay = holdDelay
            holdTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, self.pressed == chord, !self.usedWithOtherKey,
                      !self.controller.isActive
                else { return }
                self.controller.holdPressed(into: panelField())
                self.startedHold = true
            }
        case .otherKey:
            guard pressed != nil else { return }
            usedWithOtherKey = true
            holdTask?.cancel()
            if startedHold {
                controller.cancel()
                startedHold = false
            }
        case .up(let chord):
            guard chord == pressed else { return }
            pressed = nil
            holdTask?.cancel()
            let isTap = now().timeIntervalSince(pressedAt) < Self.tapLimit && !usedWithOtherKey
            let longChord = preferences().dictationLongKey
            if startedHold {
                if isTap, chord == longChord {
                    controller.keepListening()
                } else {
                    controller.holdReleased()
                }
            } else if isTap, chord == longChord {
                controller.longPressed(into: panelField())
            }
            startedHold = false
        }
    }
}
