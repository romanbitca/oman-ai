import OmanCore
import SwiftUI

struct WritingSettingsView: View {
    let model: SettingsViewModel

    var body: some View {
        SettingsForm {
            Section {
                // Choosing a model that can't be used leaves the choice where it was and says why below.
                Picker(selection: Binding(get: { model.selectedModel }, set: { model.setModel($0) })) {
                    ForEach(WritingModel.allCases) { option in
                        Text(title(for: option)).tag(option)
                    }
                } label: {
                    Text("Model")
                    Text(model.selectedModel.tagline)
                }
                if let error = model.modelError {
                    SettingsError(text: error)
                }
                if !model.selectedModel.isLocal {
                    Picker(selection: model.preference(\.quality)) {
                        ForEach(WritingQuality.allCases) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    } label: {
                        Text("How long Claude thinks")
                        Text(model.preferences.quality.detail)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                if model.selectedModel.isLocal {
                    Text(
                        "Apple's model runs on this Mac for free. It can't see the screen, only a few of your style messages fit, and it may not match your voice as closely as Claude."
                    )
                }
            }

            Section {
                TextField(text: model.preference(\.outputLanguage), prompt: Text("The language of your text")) {
                    Text("Always write in")
                }
            }

            Section {
                TextEditor(text: model.preference(\.customInstructions))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(height: 76)
                    .overlay(alignment: .topLeading) {
                        if model.preferences.customInstructions.isEmpty {
                            Text("For example: use British spelling and never use exclamation marks.")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Always follow these rules")
            } footer: {
                Text("Applies to Rewrite and Compose. Proofread only fixes mistakes.")
            }
        }
    }

    private func title(for option: WritingModel) -> String {
        model.unavailableReason(for: option) == nil ? option.displayName : "\(option.displayName) (not available)"
    }
}
