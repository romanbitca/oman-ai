import AppKit
import SwiftUI

struct AccessSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.gap) {
            SettingsTile(title: "Anthropic API key") {
                if model.hasAPIKey {
                    SettingsRow(title: "A key is saved", detail: "Stored in your Mac's Keychain.") {
                        LiquidButton(title: "Remove") { model.removeAPIKey() }
                    }
                }
                HStack(spacing: 8) {
                    SecureField(
                        "API key",
                        text: $model.apiKeyDraft,
                        prompt: Text(model.hasAPIKey ? "Replace the saved key" : "Paste your API key")
                    )
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .onSubmit(saveKey)

                    LiquidButton(title: "Save", prominent: true, action: saveKey)
                        .disabled(model.apiKeyDraft.trimmed.isEmpty || model.isValidatingKey)
                }
                if model.isValidatingKey {
                    NoticeText(text: "Checking your key…")
                }
                if let error = model.apiKeyError {
                    NoticeText(text: error)
                }
            }

            SettingsTile(title: "Permissions") {
                permissionRow(
                    title: "Accessibility",
                    detail: "Reads your selection and pastes the result.",
                    isGranted: model.isAccessibilityGranted
                ) {
                    model.requestAccessibility()
                }
                Divider()
                permissionRow(
                    title: "Screen Recording",
                    detail: "Only needed when you include the screen.",
                    isGranted: model.isScreenCaptureGranted
                ) {
                    model.requestScreenCapture()
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
        SettingsRow(title: title, detail: detail) {
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                LiquidButton(title: "Allow", prominent: true, action: action)
            }
        }
    }
}

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        SettingsTile {
            VStack(alignment: .leading, spacing: 5) {
                Text("oman").font(.system(size: 26, weight: .semibold))
                Text("Your words, in your own voice.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(version)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }

        SettingsTile {
            SettingsRow(title: "Quit oman", detail: "The menu bar icon goes away until you open the app again.") {
                LiquidButton(title: "Quit") { NSApp.terminate(nil) }
            }
        }
    }
}
