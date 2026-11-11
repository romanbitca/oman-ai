import AppKit
import OmanCore
import SwiftUI

struct ShortcutsSettingsView: View {
    let model: SettingsViewModel
    @State private var monitor: Any?

    var body: some View {
        SettingsForm {
            Section {
                ForEach(model.globalShortcutActions, id: \.self) { action in
                    row(action)
                }
            } header: {
                Text("Anywhere on your Mac")
            } footer: {
                Text("Select text in any app, then press the shortcut. The result opens in the panel.")
            }

            Section("While a result is showing") {
                ForEach(ShortcutAction.panelActions, id: \.self) { action in
                    row(action)
                }
                if let notice = model.shortcutNotice {
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                }
                if let error = model.preferencesError {
                    SettingsError(text: error)
                }
            }
        }
        .onChange(of: model.recordingAction) { syncMonitor() }
        .onDisappear {
            model.cancelRecording()
            removeMonitor()
        }
    }

    private func row(_ action: ShortcutAction) -> some View {
        LabeledContent {
            recorder(action)
        } label: {
            Text(model.title(for: action))
            if model.failedShortcuts.contains(action) {
                Text("Another app is already using this shortcut.")
            }
        }
    }

    private func recorder(_ action: ShortcutAction) -> some View {
        let isRecording = model.recordingAction == action
        let combo = model.preferences.combo(for: action)
        return HStack(spacing: 6) {
            if combo != nil, !isRecording {
                Button {
                    model.clearShortcut(for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help("Remove shortcut")
                .accessibilityLabel("Remove shortcut")
            }
            if isRecording {
                Button { model.cancelRecording() } label: {
                    Text("Press keys…").frame(minWidth: 104)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { model.startRecording(action) } label: {
                    Text(combo?.displayString ?? "Record Shortcut")
                        .foregroundStyle(combo == nil ? .secondary : .primary)
                        .frame(minWidth: 104)
                }
            }
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
