import OmanCore
import SwiftUI

struct StylesSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Divider()
            if let style = model.selectedStyle {
                StyleEditorView(model: model, style: style)
                    .id(style.id)
            } else {
                Text("Create a style from your own messages.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { model.selectedStyleID }, set: { model.selectStyle($0) })) {
                ForEach(model.styles) { style in
                    Text(style.displayName).tag(style.id)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button("New") { model.createStyle() }
                Button("Delete") { model.deleteSelectedStyle() }
                    .disabled(model.selectedStyle == nil)
                Spacer()
            }
            .padding(8)
        }
    }
}

private struct StyleEditorView: View {
    @Bindable var model: SettingsViewModel
    let style: WritingStyle

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                TextField(
                    "Name",
                    text: Binding(get: { style.name }, set: { model.updateName($0) })
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Note, for example: no emoji with clients",
                    text: Binding(get: { style.note }, set: { model.updateNote($0) })
                )
                .textFieldStyle(.roundedBorder)

                samplesSection
                Divider()
                tryItSection

                if let error = model.styleError {
                    NoticeText(text: error)
                }
            }
            .padding(16)
        }
    }

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Samples").font(.headline)
            Text("\(model.sampleSummary). Five or more samples work best.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(style.samples) { sample in
                HStack(alignment: .top, spacing: 8) {
                    Text(sample.text)
                        .font(.system(size: 12))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PanelIconButton(symbol: "xmark.circle.fill", label: "Remove sample") {
                        model.removeSample(id: sample.id)
                    }
                }
                .padding(8)
                .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }

            TextEditor(text: $model.newSampleText)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 90)
                .padding(4)
                .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            Button("Add sample") { model.addSample() }
                .disabled(model.newSampleText.trimmed.isEmpty)
        }
    }

    private var tryItSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try it").font(.headline)
            HStack(spacing: 8) {
                TextField("Type a sentence to rewrite in this style", text: $model.tryItText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.tryIt() }
                Button("Try") { model.tryIt() }
                    .disabled(model.tryItText.trimmed.isEmpty || model.isTrying)
            }
            if model.isTrying {
                ProgressView().controlSize(.small)
            }
            if !model.tryItResult.isEmpty {
                Text(model.tryItResult)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.tryItError {
                NoticeText(text: error)
            }
        }
    }
}
