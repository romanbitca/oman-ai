import Testing
@testable import OmanUI

@Suite struct LiquidGlassChoiceTests {
    @Test func panelButtonsGetInteractiveGlass() {
        #expect(LiquidGlassChoice(wantsInteraction: true, hasMotion: true).isInteractive)
    }

    @Test func settingsHasNoMotionSoItsGlassIsNeverInteractive() {
        #expect(!LiquidGlassChoice(wantsInteraction: true, hasMotion: false).isInteractive)
    }

    @Test func tilesAreNotInteractive() {
        #expect(!LiquidGlassChoice(wantsInteraction: false, hasMotion: true).isInteractive)
    }
}
