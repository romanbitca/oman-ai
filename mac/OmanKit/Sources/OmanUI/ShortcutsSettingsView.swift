import AppKit
import OmanCore
import SwiftUI

struct ShortcutsSettingsView: View {
    @Bindable var model: SettingsViewModel
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.gap) {
            SettingsTile(title: "Anywhere on your Mac") {
                ForEach(Array(model.globalShortcutActions.enumerated()), id: \.element) { index, action in
                    if index > 0 { Divider() }
                    row(action)
                }
                NoticeText(text: "Select text in any app, then press the shortcut. The result opens in the panel.")
            }

            SettingsTile(title: "While a result is showing") {
                ForEach(Array(ShortcutAction.panelActions.enumerated()), id: \.element) { index, action in
                    if index > 0 { Divider() }
                    row(action)
                }
            }

            if let notice = model.shortcutNotice {
                NoticeText(text: notice).padding(.horizontal, 6)
            }
            if let error = model.preferencesError {
                NoticeText(text: error).padding(.horizontal, 6)
            }
        }
        .onChange(of: model.recordingAction) { syncMonitor() }
        .onDisappear {
            model.cancelRecording()
            removeMonitor()
        }
    }

    private func row(_ action: ShortcutAction) -> some View {
        let failed = model.failedShortcuts.contains(action)
        return SettingsRow(
            title: model.title(for: action),
            detail: failed ? "Another app is already using this shortcut." : nil
        ) {
            recorder(action)
        }
    }

    private func recorder(_ action: ShortcutAction) -> some View {
        let isRecording = model.recordingAction == action
        let combo = model.preferences.combo(for: action)
        return HStack(spacing: 2) {
            if combo != nil, !isRecording {
                PanelIconButton(symbol: "xmark", label: "Remove shortcut") {
                    model.clearShortcut(for: action)
                }
            }
            Button {
                if isRecording {
                    model.cancelRecording()
                } else {
                    model.startRecording(action)
                }
            } label: {
                Text(isRecording ? "Press keys…" : (combo?.displayString ?? "Add shortcut"))
                    .font(.system(size: 12, weight: combo == nil ? .regular : .semibold))
                    .frame(minWidth: 96)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .foregroundStyle(isRecording ? Color.white : (combo == nil ? Color.secondary : Color.primary))
                    .background(isRecording ? Liquid.accent : Color.primary.opacity(0.07), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(LiquidPressStyle())
        }
    }

    private func syncMonitor() {
        guard model.recordingAction != nil else {
            removeMonitor()
            return
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event)
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard model.recordingAction != nil else { return event }
        let escape: UInt16 = 53
        if event.keyCode == escape {
            model.cancelRecording()
            return nil
        }
        let combo = KeyCombo(keyCode: event.keyCode, modifiers: event.modifierFlags.rawValue)
        if combo.isUsable {
            model.finishRecording(with: combo)
        } else {
            NSSound.beep()
        }
        return nil
    }
}
