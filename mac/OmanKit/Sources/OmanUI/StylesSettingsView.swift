import OmanCore
import SwiftUI

struct StyleEditorView: View {
    @Bindable var model: SettingsViewModel
    let style: WritingStyle

    private let card = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Name", text: Binding(get: { style.name }, set: { model.updateName($0) }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .semibold))

                    TextField(
                        "Note, for example: no emoji with clients",
                        text: Binding(get: { style.note }, set: { model.updateNote($0) })
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }

                samplesSection
                tryItSection

                if let error = model.styleError {
                    NoticeText(text: error)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.automatic)
    }

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Samples").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(model.sampleSummary). Five or more work best.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(style.samples) { sample in
                HStack(alignment: .top, spacing: 8) {
                    Text(sample.text)
                        .font(.system(size: 13))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PanelIconButton(symbol: "xmark", label: "Remove sample") {
                        model.removeSample(id: sample.id)
                    }
                }
                .padding(.leading, 13)
                .padding(.trailing, 6)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05), in: card)
            }

            VStack(alignment: .trailing, spacing: 8) {
                TextEditor(text: $model.newSampleText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focusEffectDisabled()
                    .frame(height: 96)
                    .overlay(alignment: .topLeading) {
                        if model.newSampleText.isEmpty {
                            Text("Paste a real message you wrote")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }

                LiquidButton(title: "Add sample", symbol: "plus", prominent: true) { model.addSample() }
                    .disabled(model.newSampleText.trimmed.isEmpty)
            }
            .padding(11)
            .background(Color.primary.opacity(0.05), in: card)
        }
    }

    private var tryItSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try it").font(.system(size: 15, weight: .semibold))

            HStack(spacing: 8) {
                TextField("Type a sentence to rewrite in this style", text: $model.tryItText)
                    .textFieldStyle(.plain)
                    .focusEffectDisabled()
                    .font(.system(size: 13))
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                    .onSubmit { model.tryIt() }
                LiquidButton(title: "Try") { model.tryIt() }
                    .disabled(model.tryItText.trimmed.isEmpty || model.isTrying)
            }

            if model.isTrying {
                ProgressView().controlSize(.small)
            }
            if !model.tryItResult.isEmpty {
                Text(model.tryItResult)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(Color.primary.opacity(0.05), in: card)
            }
            if let error = model.tryItError {
                NoticeText(text: error)
            }
        }
    }
}
