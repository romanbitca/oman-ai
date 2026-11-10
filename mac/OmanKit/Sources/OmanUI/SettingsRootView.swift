import SwiftUI

private enum SettingsPane: Hashable {
    case general
    case style(UUID)
}

public struct SettingsRootView: View {
    @Bindable private var model: SettingsViewModel
    @State private var pane: SettingsPane? = .general

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Label("General", systemImage: "gearshape").tag(SettingsPane.general)
                Section("Styles") {
                    ForEach(model.styles) { style in
                        Label(style.displayName, systemImage: "quote.bubble")
                            .lineLimit(1)
                            .tag(SettingsPane.style(style.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(220)
            .safeAreaInset(edge: .bottom) { styleButtons }
        } detail: {
            detail
        }
        .frame(width: 800, height: 580)
        .onChange(of: pane) {
            if case .style(let id) = pane { model.selectStyle(id) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .style:
            if let style = model.selectedStyle {
                StyleEditorView(model: model, style: style).id(style.id)
            }
        default:
            GeneralSettingsView(model: model)
        }
    }

    private var styleButtons: some View {
        HStack(spacing: 8) {
            LiquidButton(title: "New style", symbol: "plus") {
                model.createStyle()
                pane = model.selectedStyleID.map(SettingsPane.style)
            }
            if case .style = pane {
                LiquidButton(title: "Delete", symbol: "trash") {
                    model.deleteSelectedStyle()
                    pane = model.selectedStyleID.map(SettingsPane.style) ?? .general
                }
                .labelStyle(.iconOnly)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}
