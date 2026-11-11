import CoreGraphics
import Testing
@testable import OmanUI

@Suite struct LiquidGlassChoiceTests {
    @Test func panelButtonsGetClearInteractiveGlass() {
        let choice = LiquidGlassChoice(prefersClear: true, isTinted: false, wantsInteraction: true, hasMotion: true)
        #expect(choice == LiquidGlassChoice(prefersClear: true, isTinted: false, wantsInteraction: true, hasMotion: true))
        #expect(choice.isClear)
        #expect(choice.isInteractive)
    }

    @Test func tintedGlassStaysRegularSoItsColourHolds() {
        let choice = LiquidGlassChoice(prefersClear: true, isTinted: true, wantsInteraction: true, hasMotion: true)
        #expect(!choice.isClear)
        #expect(choice.isInteractive)
    }

    @Test func settingsHasNoMotionSoItsGlassIsNeverInteractive() {
        let choice = LiquidGlassChoice(prefersClear: false, isTinted: false, wantsInteraction: true, hasMotion: false)
        #expect(!choice.isClear)
        #expect(!choice.isInteractive)
    }

    @Test func tilesAreNotInteractive() {
        let choice = LiquidGlassChoice(prefersClear: true, isTinted: false, wantsInteraction: false, hasMotion: true)
        #expect(choice.isClear)
        #expect(!choice.isInteractive)
    }
}

@Suite struct PanelBackdropLayoutTests {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func aPanelOnTheRightGetsABandFromTheRightEdgeThatCoversItAndFadesBeyond() {
        let tiles = CGRect(x: 1000, y: 500, width: 360, height: 440)
        let layout = PanelBackdropLayout(screen: laptop, menuBarBottom: 949, tiles: tiles)

        #expect(layout.isAnchoredRight)
        // From the right edge to the tiles (512), then 60 at full strength and a 280 fade.
        #expect(layout.frame == CGRect(x: 660, y: 0, width: 852, height: 949))
        #expect(abs(layout.fadeFraction - 280.0 / 852.0) < 1e-9)
        #expect(layout.frame.minX + layout.frame.width * layout.fadeFraction < tiles.minX)
    }

    @Test func aPanelNearTheEdgeStillSitsInAWideBand() {
        let tiles = CGRect(x: 1250, y: 500, width: 240, height: 440)
        let layout = PanelBackdropLayout(screen: laptop, menuBarBottom: 949, tiles: tiles)

        #expect(abs(layout.frame.width - 1512 * PanelBackdropLayout.minimumShare) < 1e-9)
        #expect(layout.frame.maxX == laptop.maxX)
    }

    @Test func aPanelOnTheLeftGetsABandFromTheLeftEdge() {
        let tiles = CGRect(x: 100, y: 500, width: 360, height: 440)
        let layout = PanelBackdropLayout(screen: laptop, menuBarBottom: 949, tiles: tiles)

        #expect(!layout.isAnchoredRight)
        #expect(layout.frame == CGRect(x: 0, y: 0, width: 800, height: 949))
    }

    @Test func theBandNeverLeavesItsScreen() {
        let second = CGRect(x: 1512, y: -98, width: 800, height: 1080)
        let tiles = CGRect(x: 1812, y: 400, width: 360, height: 440)
        let layout = PanelBackdropLayout(screen: second, menuBarBottom: 950, tiles: tiles)

        #expect(layout.frame == CGRect(x: 1512, y: -98, width: 800, height: 1048))
        #expect(abs(layout.fadeFraction - 280.0 / 800.0) < 1e-9)
    }
}
