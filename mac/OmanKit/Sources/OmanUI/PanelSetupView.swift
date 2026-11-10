import SwiftUI

struct PanelSetupView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        GlassTile(id: LiquidID.body, padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set up oman").font(.system(size: 15, weight: .semibold))

                VStack(alignment: .leading, spacing: 9) {
                    stepTitle("Anthropic API key", isDone: model.hasAPIKey)
                    if !model.hasAPIKey {
                        HStack(spacing: 8) {
                            SecureField("Paste your API key", text: $model.apiKeyDraft)
                                .textFieldStyle(.plain)
                                .focusEffectDisabled()
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                                .onSubmit(saveKey)
                            LiquidButton(title: "Save", prominent: true, action: saveKey)
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

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        stepTitle("Accessibility", isDone: model.isAccessibilityGranted)
                        Spacer()
                        if !model.isAccessibilityGranted {
                            LiquidButton(title: "Allow", prominent: model.hasAPIKey) { model.allowAccessibility() }
                        }
                    }
                    NoticeText(text: "oman needs this to read your selection and paste the result.")
                }
            }
        }
    }

    private func saveKey() {
        Task { await model.saveSetupKey() }
    }

    private func stepTitle(_ title: String, isDone: Bool) -> some View {
        Label {
            Text(title).font(.system(size: 13, weight: .medium))
        } icon: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? AnyShapeStyle(Liquid.accent) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
    }
}
