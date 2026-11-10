import SwiftUI

public struct PanelRootView: View {
    /// The window keeps this size so the glass can reshape without the window server resizing it.
    public static let windowSize = CGSize(
        width: PanelMetrics.width + PanelMetrics.sideMargin * 2,
        height: PanelMetrics.maxHeight + PanelMetrics.bottomMargin
    )

    public static let windowSideMargin = PanelMetrics.sideMargin

    private let model: PanelViewModel
    @Namespace private var space

    public init(model: PanelViewModel) {
        self.model = model
    }

    public var body: some View {
        LiquidContainer(spacing: PanelMetrics.blend) {
            ZStack(alignment: .topTrailing) {
                // Behind the tiles, so the pin and settings buttons in the corner keep their clicks.
                if model.isPinned {
                    PanelCornerHandle()
                        .padding(.top, PanelMetrics.shadowRoom)
                        .padding(.trailing, PanelMetrics.shadowRoom)
                        .transition(.opacity)
                }
                content
                    .frame(width: PanelMetrics.width)
                    .frame(maxHeight: PanelMetrics.maxHeight, alignment: .top)
                    .padding(.top, model.isPinned ? PanelMetrics.sideMargin : 0)
                    .padding(.horizontal, PanelMetrics.sideMargin)
            }
        }
        .environment(\.liquidSpace, space)
        .environment(\.panelIsFloating, model.isPinned)
        .animation(Liquid.morph, value: model.screen)
        .animation(Liquid.morph, value: model.isPinned)
        .keyframeAnimator(initialValue: 1.0, trigger: model.session) { view, opacity in
            view.opacity(opacity)
        } keyframes: { _ in
            MoveKeyframe(0)
            LinearKeyframe(1, duration: 0.12)
        }
        .padding(.bottom, PanelMetrics.bottomMargin)
        .frame(
            width: Self.windowSize.width,
            height: Self.windowSize.height,
            alignment: .top
        )
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
