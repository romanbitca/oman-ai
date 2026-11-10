import SwiftUI

public struct PanelRootView: View {
    private let model: PanelViewModel
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    public init(model: PanelViewModel) {
        self.model = model
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PanelMetrics.padding)
            .frame(width: PanelMetrics.width)
            .frame(maxHeight: PanelMetrics.maxHeight)
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .clipShape(shape)
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .setup: PanelSetupView(model: model)
        case .home: PanelHomeView(model: model)
        case .compose: PanelComposeView(model: model)
        case .working: PanelWorkingView(model: model)
        case .result: PanelResultView(model: model)
        case .failed: PanelFailedView(model: model)
        }
    }
}
