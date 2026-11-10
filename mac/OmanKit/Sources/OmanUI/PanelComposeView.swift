import SwiftUI

struct PanelComposeView: View {
    @Bindable var model: PanelViewModel
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        PanelScrollArea {
            VStack(alignment: .leading, spacing: 12) {
                header

                TextField("What do you want to write?", text: $model.composePrompt, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.plain)
                    .focused($isPromptFocused)
                    .focusEffectDisabled()
                    .onSubmit { model.compose() }
                    .padding(10)
                    .background(
                        Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                if model.capture.text != nil {
                    NoticeText(text: "Using your selected text as reference")
                }

                StyleChipsView(
                    styles: model.styles,
                    selectedID: model.selectedStyleID,
                    onSelect: { model.toggleComposeStyle($0) },
                    onCreate: { model.openSettings() }
                )

                ContextSectionView(model: model)

                HStack {
                    Spacer()
                    Button("Write") { model.compose() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canCompose)
                }
            }
        }
        .task(id: model.session) { isPromptFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if model.canGoBackFromCompose {
                PanelIconButton(symbol: "chevron.left", label: "Back") { model.backToHome() }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Compose").font(.headline)
                if let name = model.sourceAppName {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            PanelHeaderButtons(model: model)
        }
    }
}
