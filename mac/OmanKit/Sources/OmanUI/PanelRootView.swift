import SwiftUI

/// How far along the panel is in appearing.
struct PanelEntrance {
    /// Points above its resting place when it starts.
    static let startLift: CGFloat = 8
    var opacity = 1.0
    var lift: CGFloat = 0
}

public struct PanelRootView: View {
    /// The window keeps this size so the glass can reshape without the window server resizing it.
    public static let windowSize = CGSize(
        width: PanelMetrics.width + PanelMetrics.sideMargin * 2,
        height: PanelMetrics.menuBarGap + PanelMetrics.maxHeight + PanelMetrics.bottomMargin
    )

    public static let windowSideMargin = PanelMetrics.sideMargin

    /// Where the tiles are on screen while the panel hangs from the menu bar: `contentHeight` tall, below the
    /// gap at the top of the panel's window and between its side margins.
    public static func tilesFrame(inWindow frame: CGRect, contentHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX + PanelMetrics.sideMargin,
            y: frame.maxY - PanelMetrics.menuBarGap - contentHeight,
            width: frame.width - PanelMetrics.sideMargin * 2,
            height: contentHeight
        )
    }

    private let model: PanelViewModel
    private let hasBackdrop: Bool
    @Namespace private var space
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    /// `hasBackdrop` says whether the app draws `PanelBackdrop` behind the unpinned panel.
    public init(model: PanelViewModel, hasBackdrop: Bool = false) {
        self.model = model
        self.hasBackdrop = hasBackdrop
    }

    /// The backdrop is what makes clear glass readable. Pinned, the panel floats over whatever the person is
    /// working in with no backdrop, so it keeps frosted glass there.
    public static func showsBackdrop(isAvailable: Bool, isPinned: Bool, reduceTransparency: Bool) -> Bool {
        isAvailable && !isPinned && !reduceTransparency
    }

    /// Clear glass is Control Center's dark glass with white text. With the Light theme the tiles stay frosted.
    private var usesClearGlass: Bool {
        colorScheme == .dark
            && Self.showsBackdrop(isAvailable: hasBackdrop, isPinned: model.isPinned, reduceTransparency: reduceTransparency)
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            // Behind the tiles, so the pin and settings buttons in the corner keep their clicks.
            if model.isPinned {
                PanelCornerHandle()
                    .padding(.top, PanelMetrics.shadowRoom)
                    .padding(.trailing, PanelMetrics.shadowRoom)
                    .transition(.opacity)
            }
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.contentHeightChanged($0) }
                .frame(width: PanelMetrics.width)
                .frame(maxHeight: PanelMetrics.maxHeight, alignment: .top)
                // The window hangs from the menu bar's lower edge, so the gap below the bar is inside it. That
                // also leaves the panel room to drop into place without being cut off at the window's top.
                .padding(.top, model.isPinned ? PanelMetrics.sideMargin : PanelMetrics.menuBarGap)
                .padding(.horizontal, PanelMetrics.sideMargin)
        }
        .saturation(Liquid.colorBoost(usesClearGlass: usesClearGlass))
        .environment(\.liquidColorBoost, Liquid.colorBoost(usesClearGlass: usesClearGlass))
        .environment(\.liquidSpace, space)
        .environment(\.panelIsFloating, model.isPinned)
        .environment(\.liquidClearGlass, usesClearGlass)
        .withoutSystemWritingTools()
        .animation(Liquid.morph, value: model.screen)
        .animation(Liquid.morph, value: model.isPinned)
        // The panel arrives from the menu bar it hangs under: it fades in fast while it drops the last few points.
        // Growing instead, as Control Center does, halved the frame rate while it played: glass is redrawn
        // for every size, and only moved for a slide.
        .keyframeAnimator(initialValue: PanelEntrance(), trigger: model.session) { view, entrance in
            view
                .opacity(entrance.opacity)
                .offset(y: -entrance.lift)
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0)
                LinearKeyframe(1, duration: 0.1)
            }
            KeyframeTrack(\.lift) {
                MoveKeyframe(PanelEntrance.startLift)
                SpringKeyframe(0, duration: 0.26, spring: .smooth)
            }
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
        case .setup: PanelSetupView(model: model).transition(Liquid.swap)
        case .home: PanelHomeView(model: model).transition(Liquid.swap)
        case .compose: PanelComposeView(model: model).transition(Liquid.swap)
        case .working: PanelWorkingView(model: model).transition(Liquid.swap)
        case .result: PanelResultView(model: model).transition(Liquid.swap)
        case .failed: PanelFailedView(model: model).transition(Liquid.swap)
        }
    }
}
