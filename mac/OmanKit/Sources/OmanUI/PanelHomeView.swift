import SwiftUI

struct PanelHomeView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        PanelScrollArea {
            VStack(alignment: .leading, spacing: 12) {
                header

                PanelInputField(symbol: "sparkles", prompt: "Describe your change", text: $model.instruction) {
                    model.rewrite()
                }

                HStack(spacing: 8) {
                    ActionCard(title: "Proofread", symbol: "text.magnifyingglass") { model.proofread() }
                    ActionCard(title: "Rewrite", symbol: "arrow.triangle.2.circlepath") { model.rewrite() }
                }

                StyleChipsView(
                    styles: model.styles,
                    selectedID: model.selectedStyleID,
                    onSelect: { model.chooseStyleAndRewrite($0) },
                    onCreate: { model.openSettings() }
                )

                ContextSectionView(model: model)

                Divider()

                Button {
                    model.openCompose()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                        Text("Compose").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PanelCardButtonStyle())
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let name = model.sourceAppName {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
                Text(model.capture.text ?? "")
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            PanelHeaderButtons(model: model)
        }
    }
}
