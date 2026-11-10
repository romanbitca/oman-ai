import AppKit
import OmanCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Anthropic API key") {
                if model.hasAPIKey {
                    HStack {
                        Label("A key is saved", systemImage: "checkmark.circle.fill")
                        Spacer()
                        Button("Remove") { model.removeAPIKey() }
                    }
                }
                HStack(spacing: 8) {
                    SecureField(
                        "API key",
                        text: $model.apiKeyDraft,
                        prompt: Text(model.hasAPIKey ? "Replace the saved key" : "Paste your API key")
                    )
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(model.apiKeyDraft.trimmed.isEmpty || model.isValidatingKey)
                }
                if model.isValidatingKey {
                    NoticeText(text: "Checking your key…")
                }
                if let error = model.apiKeyError {
                    NoticeText(text: error)
                }
            }

            Section {
                Picker(
                    "Model",
                    selection: Binding(get: { model.selectedModel }, set: { model.setModel($0) })
                ) {
                    ForEach(ClaudeModel.allCases) { option in
                        Text("\(option.displayName): \(option.tagline)").tag(option)
                    }
                }
                if let error = model.modelError {
                    NoticeText(text: error)
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
                    detail: "Only needed for Include screen.",
                    isGranted: model.isScreenCaptureGranted
                ) {
                    model.requestScreenCapture()
                }
            }

            Section {
                Toggle(
                    "Open at login",
                    isOn: Binding(get: { model.isLaunchAtLogin }, set: { model.setLaunchAtLogin($0) })
                )
                if let error = model.launchAtLoginError {
                    NoticeText(text: error)
                }
            }
        }
        .formStyle(.grouped)
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
            } else {
                Button("Allow", action: action)
            }
        }
    }
}
