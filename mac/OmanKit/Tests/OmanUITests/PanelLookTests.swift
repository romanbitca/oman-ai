import CoreGraphics
import Testing
@testable import OmanUI

@Suite struct LiquidGlassChoiceTests {
    @Test func panelButtonsGetClearInteractiveGlass() {
        let choice = LiquidGlassChoice(prefersClear: true, isTinted: false, wantsInteraction: true, hasMotion: true)
        #expect(choice.isClear)
        #expect(choice.isInteractive)
    }

    @Test func tintedGlassStaysFrostedSoItsColourHolds() {
        #expect(!LiquidGlassChoice(prefersClear: true, isTinted: true, wantsInteraction: true, hasMotion: true).isClear)
    }

    @Test func settingsHasNoMotionSoItsGlassIsNeverInteractive() {
        let choice = LiquidGlassChoice(prefersClear: false, isTinted: false, wantsInteraction: true, hasMotion: false)
        #expect(!choice.isClear)
        #expect(!choice.isInteractive)
    }

    @Test func tilesAreNotInteractive() {
        #expect(!LiquidGlassChoice(prefersClear: true, isTinted: false, wantsInteraction: false, hasMotion: true).isInteractive)
    }
}

@MainActor
@Suite struct PanelHaloTests {
    private let edge = PanelHalo.maskEdge
    private let radius = Int(PanelMetrics.tileRadius)

    @Test func theBlurIsFullInsideTheTilesOutline() {
        #expect(PanelHalo.maskAlpha(x: edge, y: edge) == 255)
        // Along a straight side, all the way to the tiles' edge.
        #expect(PanelHalo.maskAlpha(x: edge, y: edge - radius) == 255)
    }

    @Test func itFadesOutOverTheSpreadBeyondTheTiles() {
        let halfway = edge - radius - Int(PanelHalo.spread / 2)
        #expect((100...155).contains(Int(PanelHalo.maskAlpha(x: edge, y: halfway))))
        #expect(PanelHalo.maskAlpha(x: edge, y: 0) == 0)
    }

    @Test func theCornersFollowTheTilesRoundedCorners() {
        // Diagonally out from the middle, the tiles' corner arc is at the corner radius.
        let onArc = edge - Int((PanelMetrics.tileRadius / 2.squareRoot()).rounded()) + 1
        #expect(PanelHalo.maskAlpha(x: onArc, y: onArc) > 230)
        #expect(PanelHalo.maskAlpha(x: 0, y: 0) == 0)
    }

    @Test func theMaskStretchesFromItsMiddle() {
        #expect(PanelHalo.mask.resizingMode == .stretch)
        #expect(PanelHalo.mask.capInsets.top == CGFloat(edge))
    }
}
