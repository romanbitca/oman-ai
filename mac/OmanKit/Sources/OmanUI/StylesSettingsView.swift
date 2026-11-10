import OmanCore
import SwiftUI

struct StylesSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        SettingsTile(title: "Your styles") {
            FlowLayout(spacing: 6) {
                ForEach(model.styles) { style in
                    styleChip(style)
                }
                Button {
                    model.createStyle()
                } label: {
                    Label("New style", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(LiquidPressStyle())
            }
        }

        if !model.styles.isEmpty {
            SettingsTile(title: "Choosing a style") {
                SettingsRow(title: "Default style", detail: "Selected when an app has no style of its own yet.") {
                    Picker(
                        "Default style",
                        selection: Binding(
                            get: { model.preferences.defaultStyleID },
                            set: { value in model.updatePreferences { $0.defaultStyleID = value } }
                        )
                    ) {
                        Text("None").tag(UUID?.none)
                        ForEach(model.styles) { style in
                            Text(style.displayName).tag(UUID?.some(style.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                Divider()
                SettingsToggleRow(
                    title: "Remember the last style in each app",
                    detail: "Slack can keep one style and Mail another.",
                    isOn: Binding(
                        get: { model.preferences.remembersStylePerApp },
                        set: { value in model.updatePreferences { $0.remembersStylePerApp = value } }
                    )
                )
            }
        }

        if let style = model.selectedStyle {
            StyleEditorView(model: model, style: style).id(style.id)
        }

        if let error = model.styleError {
            NoticeText(text: error).padding(.horizontal, 6)
        }
    }

    private func styleChip(_ style: WritingStyle) -> some View {
        let isSelected = style.id == model.selectedStyleID
        return Button {
            model.selectStyle(style.id)
        } label: {
            Text(style.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Liquid.accent : Color.primary.opacity(0.07), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(LiquidPressStyle())
    }
}

private struct StyleEditorView: View {
    @Bindable var model: SettingsViewModel
    let style: WritingStyle

    var body: some View {
        SettingsTile {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    TextField("Style name", text: Binding(get: { style.name }, set: { model.updateName($0) }))
                        .textFieldStyle(.plain)
                        .focusEffectDisabled()
                        .font(.system(size: 20, weight: .semibold))
                    TextField(
                        "Add a note, for example: no emoji with clients",
                        text: Binding(get: { style.note }, set: { model.updateNote($0) })
                    )
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                PanelIconButton(symbol: "trash", label: "Delete style") {
                    model.deleteSelectedStyle()
                }
            }
        }

        SettingsTile {
            HStack(alignment: .firstTextBaseline) {
                Text("Your messages").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(model.sampleSummary). Five or more work best.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            ForEach(style.samples) { sample in
                HStack(alignment: .top, spacing: 8) {
                    Text(sample.text)
                        .font(.system(size: 13))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PanelIconButton(symbol: "xmark", label: "Remove message") {
                        model.removeSample(id: sample.id)
                    }
                }
                .padding(.leading, 13)
                .padding(.trailing, 6)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.07), in: SettingsMetrics.inset)
            }

            SettingsTextBox(prompt: "Paste a real message you wrote", text: $model.newSampleText)

            HStack {
                Spacer()
                LiquidButton(title: "Add message", symbol: "plus", prominent: true) { model.addSample() }
                    .disabled(model.newSampleText.trimmed.isEmpty)
            }
        }

        SettingsTile(title: "Try it") {
            HStack(spacing: 8) {
                SettingsTextField(prompt: "Type a sentence to rewrite in this style", text: $model.tryItText) {
                    model.tryIt()
                }
                LiquidButton(title: "Try") { model.tryIt() }
                    .disabled(model.tryItText.trimmed.isEmpty || model.isTrying)
            }
            if model.isTrying, model.tryItResult.isEmpty {
                Text("Writing…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if !model.tryItResult.isEmpty {
                Text(model.tryItResult)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(Color.primary.opacity(0.07), in: SettingsMetrics.inset)
            }
            if let error = model.tryItError {
                NoticeText(text: error)
            }
        }
    }
}
