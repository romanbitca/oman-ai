import SwiftUI

struct PanelComposeView: View {
    @Bindable var model: PanelViewModel
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        PanelScrollArea {
            VStack(alignment: .leading, spacing: PanelMetrics.gap) {
                GlassTile(id: LiquidID.header, padding: 10) { header }

                TextField("What do you want to write?", text: $model.composePrompt, axis: .vertical)
                    .lineLimit(4...9)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isPromptFocused)
                    .focusEffectDisabled()
                    .onSubmit { model.compose() }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(PanelShape.tile)
                    .onTapGesture { isPromptFocused = true }
                    .liquidGlass(in: PanelShape.tile, id: LiquidID.body, reading: true)

                if model.capture.text != nil {
                    NoticeText(text: "Using your selected text as reference")
                        .padding(.horizontal, 6)
                }

                PanelControlsGroup {
                    StyleChipsView(
                        styles: model.styles,
                        selectedID: model.selectedStyleID,
                        onSelect: { model.toggleComposeStyle($0) },
                        onCreate: { model.openSettings() }
                    )

                    ContextSectionView(model: model)
                }

                HStack {
                    Spacer()
                    LiquidButton(title: "Write", symbol: "arrow.up", prominent: true) { model.compose() }
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
            SourceAppIcon(bundleID: model.capture.app?.bundleID)
            VStack(alignment: .leading, spacing: 1) {
                Text("Compose").font(.system(size: 13, weight: .semibold))
                if let name = model.sourceAppName {
                    Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            PanelHeaderButtons(model: model)
        }
    }
}
