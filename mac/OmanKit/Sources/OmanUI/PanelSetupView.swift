import SwiftUI

struct PanelSetupView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        GlassTile(id: LiquidID.body, padding: 16, reading: true) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set up OmanAI").font(.system(size: 15, weight: .semibold))

                VStack(alignment: .leading, spacing: 9) {
                    stepTitle(model.usesLocalModel ? "Apple on-device model" : "Anthropic API key", isDone: model.isKeyStepDone)
                    if !model.isKeyStepDone {
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
                        if model.canUseAppleModel {
                            Button("Use Apple's on-device model instead") { model.useAppleModel() }
                                .buttonStyle(LiquidPressStyle())
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Liquid.accent)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        stepTitle("Accessibility", isDone: model.isAccessibilityGranted)
                        Spacer()
                        if !model.isAccessibilityGranted {
                            LiquidButton(title: "Allow", prominent: model.isKeyStepDone) { model.allowAccessibility() }
                        }
                    }
                    NoticeText(text: "OmanAI needs this to read your selection and paste the result.")
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
