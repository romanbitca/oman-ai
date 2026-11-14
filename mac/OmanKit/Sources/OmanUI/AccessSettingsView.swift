#if os(macOS)
import AppKit
import SwiftUI

struct AccessSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        SettingsForm {
            Section("Anthropic API key") {
                if model.hasAPIKey {
                    LabeledContent {
                        Button("Remove") { model.removeAPIKey() }
                    } label: {
                        Text("A key is saved")
                        Text("Stored in your Mac's Keychain.")
                    }
                }
                HStack(spacing: 8) {
                    SecureField(
                        "API key",
                        text: $model.apiKeyDraft,
                        prompt: Text(model.hasAPIKey ? "Replace the saved key" : "Paste your API key")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(model.apiKeyDraft.trimmed.isEmpty || model.isValidatingKey)
                }
                if model.isValidatingKey {
                    Text("Checking your key…").font(.callout).foregroundStyle(.secondary)
                }
                if let error = model.apiKeyError {
                    SettingsError(text: error)
                }
            }

            Section("Permissions") {
                permissionRow(
                    title: "Accessibility",
                    detail: "Reads your selection and pastes the result.",
                    isGranted: model.isAccessibilityGranted
                ) {
                    model.requestAccessibility()
                }
                permissionRow(
                    title: "Screen Recording",
                    detail: "Only needed when you include the screen.",
                    isGranted: model.isScreenCaptureGranted
                ) {
                    model.requestScreenCapture()
                }
                permissionRow(
                    title: "Microphone",
                    detail: model.microphoneAccess == .denied
                        ? "Turn on OmanAI in System Settings, under Privacy & Security, then Microphone."
                        : "Only needed when you dictate.",
                    isGranted: model.microphoneAccess == .granted
                ) {
                    model.allowMicrophone()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
    }

    private func saveKey() {
        Task { await model.saveAPIKey() }
    }

    private func permissionRow(
        title: String,
        detail: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            if isGranted {
                Label {
                    Text("Allowed").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                Button("Allow…", action: action)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}
#endif
