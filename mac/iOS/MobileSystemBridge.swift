import AudioToolbox
import AVFoundation
import OmanCore
import UIKit

/// What the shared code asks of the system, on the iPhone. There is no other app's selection to read or paste into,
/// no Accessibility and no global shortcut: the text is typed, pasted or dictated into OmanAI itself, and what is
/// finished goes to the clipboard, to paste in any app.
@MainActor
final class MobileSystemBridge: SystemBridging {
    private enum Unavailable: LocalizedError {
        case screen
        var errorDescription: String? { "The iPhone can't include another app's screen." }
    }

    // MARK: Permissions

    /// Nothing on the iPhone needs Accessibility, so the panel never waits for it.
    var isAccessibilityGranted: Bool { true }
    func requestAccessibility() {}

    var isScreenCaptureGranted: Bool { false }
    func requestScreenCapture() {}

    var microphoneAccess: MicrophoneAccess {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .undetermined: .notDetermined
        default: .denied
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func openMicrophoneSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Apps and keys

    var frontmostApp: SourceApp? { nil }
    func rememberFocus(in app: SourceApp) {}

    var onModifierKey: (@MainActor (ModifierKeyEvent) -> Void)?
    func watchModifierKeys(_ chords: Set<ModifierChord>) {}

    func playSound(_ sound: DictationSound) {
        // The keyboard's own clicks, which follow the ring switch and the phone's sound settings.
        AudioServicesPlaySystemSound(sound == .start ? 1113 : 1114)
    }

    func setOutputMuted(_ muted: Bool) {}
    func pressReturn(withCommand: Bool) {}

    var isLaunchAtLoginEnabled: Bool { false }
    func setLaunchAtLogin(_ enabled: Bool) throws {}

    // MARK: Text

    func captureSelection() async -> SelectionCapture {
        SelectionCapture(app: nil, text: nil)
    }

    func replaceSelection(expected: String, with text: String, in app: SourceApp) async -> InsertOutcome {
        .sourceUnavailable
    }

    /// A dictation finished outside the panel's fields goes to the clipboard, ready to paste in any app.
    func insertAtCursor(_ text: String, in app: SourceApp?) async -> InsertOutcome {
        UIPasteboard.general.string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return .inserted
    }

    func textFocus() async -> TextFocus { .takesText }

    @discardableResult
    func switchOnFocusReporting() async -> Bool { false }
    func switchOffFocusReporting() {}

    func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }

    func applicationURL(named name: String) -> URL? { nil }

    /// Asks only whether there is text, which doesn't bring up iOS's question about pasting.
    var hasClipboardText: Bool { UIPasteboard.general.hasStrings }

    func clipboardText() -> String? {
        UIPasteboard.general.string
    }

    func captureWindow(of app: SourceApp) async throws -> ScreenshotAttachment {
        throw Unavailable.screen
    }

    func setAppearance(_ mode: AppearanceMode) {
        let style: UIUserInterfaceStyle = switch mode {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.overrideUserInterfaceStyle = style }
        }
    }

    // MARK: Shortcuts, which the iPhone doesn't have

    var onGlobalShortcut: (@MainActor (ShortcutAction) -> Void)?
    var onGlobalShortcutReleased: (@MainActor (ShortcutAction) -> Void)?

    @discardableResult
    func registerGlobalShortcuts(_ shortcuts: [ShortcutAction: KeyCombo]) -> Set<ShortcutAction> { [] }
    func suspendGlobalShortcuts() {}

    @discardableResult
    func setTemporaryShortcut(_ combo: KeyCombo?, for action: ShortcutAction) -> Bool { false }
}
