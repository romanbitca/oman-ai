import SwiftUI

struct PanelHomeView: View {
    @Bindable var model: PanelViewModel

    var body: some View {
        PanelScrollArea {
            VStack(alignment: .leading, spacing: PanelMetrics.gap) {
                GlassTile(id: LiquidID.header) { header }

                PanelInputField(symbol: "sparkle", prompt: "Describe your change", text: $model.instruction) {
                    model.rewrite()
                }

                HStack(spacing: PanelMetrics.gap) {
                    ActionCard(title: "Proofread", symbol: "text.magnifyingglass") { model.proofread() }
                    ActionCard(title: "Rewrite", symbol: "arrow.trianglehead.2.clockwise") { model.rewrite() }
                    ActionCard(title: "Explain", symbol: "lightbulb") { model.explain() }
                        .help("See how a reader will understand your text")
                }

                StyleChipsView(
                    styles: model.styles,
                    selectedID: model.selectedStyleID,
                    onSelect: { model.chooseStyleAndRewrite($0) },
                    onCreate: { model.openSettings() }
                )

                ContextSectionView(model: model)

                composeRow
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 9) {
            SourceAppIcon(bundleID: model.capture.app?.bundleID)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                if let name = model.sourceAppName {
                    Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(model.capture.text ?? "")
                    .font(.system(size: 13))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            PanelHeaderButtons(model: model)
                .padding(.top, -3)
                .padding(.trailing, -3)
        }
    }

    private var composeRow: some View {
        Button {
            model.openCompose()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .medium))
                Text("Compose").font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 15)
            .frame(height: 42)
            .contentShape(Capsule())
            .liquidGlass(in: Capsule(), id: LiquidID.actions, interactive: true)
        }
        .buttonStyle(GlassPressStyle())
    }
}
