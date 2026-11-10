import SwiftUI

struct PanelSetupView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up oman").font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                stepTitle("Anthropic API key", isDone: model.hasAPIKey)
                if !model.hasAPIKey {
                    HStack(spacing: 8) {
                        SecureField("Paste your API key", text: $model.apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveKey)
                        Button("Save", action: saveKey)
                            .disabled(model.apiKeyDraft.trimmed.isEmpty || model.isValidatingKey)
                    }
                    if model.isValidatingKey {
                        NoticeText(text: "Checking your key…")
                    }
                    if let error = model.setupError {
                        NoticeText(text: error)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    stepTitle("Accessibility", isDone: model.isAccessibilityGranted)
                    Spacer()
                    if !model.isAccessibilityGranted {
                        Button("Allow") { model.allowAccessibility() }
                    }
                }
                NoticeText(text: "oman needs this to read your selection and paste the result.")
            }
        }
    }

    private func saveKey() {
        Task { await model.saveSetupKey() }
    }

    private func stepTitle(_ title: String, isDone: Bool) -> some View {
        Label(title, systemImage: isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 13, weight: .medium))
    }
}
