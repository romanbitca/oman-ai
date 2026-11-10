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
            content
                .frame(width: PanelMetrics.width)
                .frame(maxHeight: PanelMetrics.maxHeight, alignment: .top)
        }
        .environment(\.liquidSpace, space)
        .animation(Liquid.morph, value: model.screen)
        .keyframeAnimator(initialValue: DropValues(), trigger: model.session) { view, drop in
            view
                .scaleEffect(x: drop.width, y: drop.height, anchor: .top)
                .opacity(drop.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.height) {
                MoveKeyframe(0.45)
                SpringKeyframe(1, duration: 0.42, spring: .init(response: 0.42, dampingRatio: 0.62))
            }
            KeyframeTrack(\.width) {
                MoveKeyframe(0.74)
                SpringKeyframe(1, duration: 0.42, spring: .init(response: 0.42, dampingRatio: 0.7))
            }
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0)
                LinearKeyframe(1, duration: 0.12)
            }
        }
        .padding(.horizontal, PanelMetrics.sideMargin)
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

private struct DropValues {
    var width: CGFloat = 1
    var height: CGFloat = 1
    var opacity: Double = 1
}
