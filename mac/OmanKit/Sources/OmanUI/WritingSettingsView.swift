import OmanCore
import SwiftUI

struct WritingSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        SettingsTile(title: "Model") {
            HStack(spacing: 8) {
                ForEach(WritingModel.allCases) { option in
                    modelCard(option)
                }
            }
            if let error = model.modelError {
                NoticeText(text: error)
            }
        }

        if model.selectedModel.isLocal {
            SettingsTile {
                NoticeText(
                    text: "Apple's model runs on this Mac for free. It can't see the screen, only a few of your style messages fit, and it may not match your voice as closely as Claude."
                )
            }
        } else {
            SettingsTile(title: "Quality") {
                SettingsRow(title: "How long Claude thinks", detail: model.preferences.quality.detail) {
                    LiquidSegmented(
                        options: WritingQuality.allCases,
                        selection: model.preferences.quality,
                        title: \.displayName,
                        onSelect: { value in model.updatePreferences { $0.quality = value } }
                    )
                }
            }
        }

        SettingsTile(title: "Language") {
            SettingsRow(title: "Always write in", detail: "Leave empty to keep the language of your text.") {
                SettingsTextField(
                    prompt: "For example: English",
                    text: Binding(
                        get: { model.preferences.outputLanguage },
                        set: { value in model.updatePreferences { $0.outputLanguage = value } }
                    )
                )
                .frame(width: 220)
            }
        }

        SettingsTile(title: "Always follow these rules") {
            SettingsTextBox(
                prompt: "For example: use British spelling and never use exclamation marks.",
                text: Binding(
                    get: { model.preferences.customInstructions },
                    set: { value in model.updatePreferences { $0.customInstructions = value } }
                )
            )
            NoticeText(text: "Applies to Rewrite and Compose. Proofread only fixes mistakes.")
        }
    }

    private func modelCard(_ option: WritingModel) -> some View {
        let isSelected = option == model.selectedModel
        return Button {
            withAnimation(Liquid.press) { model.setModel(option) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(option.displayName).font(.system(size: 13, weight: .semibold))
                Text(model.unavailableReason(for: option) == nil ? option.tagline : "Not available")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Liquid.accent : Color.primary.opacity(0.07), in: SettingsMetrics.inset)
            .contentShape(SettingsMetrics.inset)
        }
        .buttonStyle(LiquidPressStyle())
    }
}
