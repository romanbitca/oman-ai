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

    @Test func textToReadOrTypeStaysOnFrostedGlass() {
        let choice = LiquidGlassChoice(prefersClear: true, isTinted: false, isForReading: true, wantsInteraction: false, hasMotion: true)
        #expect(!choice.isClear)
    }

    @Test func tilesAreNotInteractive() {
        #expect(!LiquidGlassChoice(prefersClear: true, isTinted: false, wantsInteraction: false, hasMotion: true).isInteractive)
    }
}

@Suite struct ClearGlassColourTests {
    @Test func clearGlassGetsControlCentersColourBoost() {
        #expect(Liquid.colorBoost(usesClearGlass: true) == Liquid.clearGlassSaturation)
        #expect(Liquid.clearGlassSaturation > 1)
    }

    @Test func frostedGlassKeepsItsColours() {
        // Pinned, with the Light theme or with Reduce Transparency on, the panel must look as it did before.
        #expect(Liquid.colorBoost(usesClearGlass: false) == 1)
    }
}

@Suite struct PanelPlacementTests {
    @Test func theTilesStartBelowTheGapAtTheTopOfTheWindow() {
        let window = CGRect(origin: CGPoint(x: 978, y: 420), size: PanelRootView.windowSize)
        let tiles = PanelRootView.tilesFrame(inWindow: window, contentHeight: 343)
        // The window hangs from the menu bar's lower edge, and the first tile starts 11 points below that.
        #expect(tiles.maxY == window.maxY - 11)
        #expect(tiles.height == 343)
        #expect(tiles.minX == window.minX + PanelMetrics.sideMargin)
        #expect(tiles.width == PanelMetrics.width)
    }

    @Test func theWindowHoldsTheGapTheTallestPanelAndItsBottomMargin() {
        #expect(PanelRootView.windowSize.height == PanelMetrics.menuBarGap + PanelMetrics.maxHeight + PanelMetrics.bottomMargin)
    }
}

@Suite struct PanelBackdropLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    private let tiles = CGRect(x: 1012, y: 779, width: 360, height: 300)
    private var layout: PanelBackdropLayout { PanelBackdropLayout(tiles: tiles, bounds: screen, cornerRadius: 22) }

    private func value(_ map: (values: [UInt8], width: Int, height: Int), of area: CGRect, x: CGFloat, y: CGFloat) -> UInt8 {
        map.values[Int((area.maxY - y) / 2) * map.width + Int((x - area.minX) / 2)]
    }

    @Test func theBlurIsFullBehindTheTilesAndGoneJustOutsideThem() {
        #expect(PanelBackdropLayout.blur(atDistance: -100) == 1)
        #expect(PanelBackdropLayout.blur(atDistance: -45) == 1)
        #expect(PanelBackdropLayout.blur(atDistance: 0) == 0.5)
        #expect(PanelBackdropLayout.blur(atDistance: 45) == 0)
        #expect(PanelBackdropLayout.blur(atDistance: 200) == 0)
    }

    @Test func theBlurMatchesControlCentersJustOutsideItsModules() {
        // Measured: half a point of blur 30 points out, and one point 14 points out.
        #expect(abs(PanelBackdropLayout.blur(atDistance: 30) * PanelBackdropLayout.blurPoints - 0.5) < 0.05)
        #expect(abs(PanelBackdropLayout.blur(atDistance: 14) * PanelBackdropLayout.blurPoints - 1.0) < 0.05)
    }

    @Test func theBlurFadesWithoutAStep() {
        // Spots a point apart never differ by more than a fiftieth of the full blur, so there is no line to see
        // where it begins.
        var previous = PanelBackdropLayout.blur(atDistance: 60)
        for distance in stride(from: 59.0, through: -60, by: -1) {
            let share = PanelBackdropLayout.blur(atDistance: distance)
            #expect(share >= previous)
            #expect(share - previous < 0.02)
            previous = share
        }
    }

    @Test func theDarkeningIsFullBehindTheTilesAndGoneFarFromThem() {
        #expect(PanelBackdropLayout.dim(atDistance: -100) == 0.10)
        #expect(PanelBackdropLayout.dim(atDistance: -34) == 0.10)
        #expect(abs(PanelBackdropLayout.dim(atDistance: 46) - 0.05) < 1e-9)
        #expect(PanelBackdropLayout.dim(atDistance: 126) == 0)
        #expect(PanelBackdropLayout.dim(atDistance: 300) == 0)
    }

    @Test func nothingIsDrawnOverTheMenuBar() {
        // The panel hangs 5 points under the menu bar, so both parts of the backdrop are cut off there.
        #expect(layout.frame == CGRect(x: 886, y: 653, width: 612, height: 431))
        #expect(layout.blurFrame == CGRect(x: 967, y: 734, width: 450, height: 350))
        #expect(layout.frame.maxY == screen.maxY)
        #expect(layout.frame.contains(layout.blurFrame))
    }

    @Test func distanceFollowsTheTilesRoundedOutline() {
        #expect(layout.distance(to: CGPoint(x: tiles.midX, y: tiles.midY)) == -150)
        #expect(abs(layout.distance(to: CGPoint(x: tiles.minX, y: tiles.midY))) < 1e-9)
        #expect(abs(layout.distance(to: CGPoint(x: tiles.minX - 40, y: tiles.midY)) - 40) < 1e-9)
        // The square corner of the tiles' frame is outside their rounded corner.
        let corner = layout.distance(to: CGPoint(x: tiles.minX, y: tiles.minY))
        #expect(abs(corner - (22 * 2.0.squareRoot() - 22)) < 1e-9)
    }

    @Test func theDarkeningIsMappedTopRowFirstAndStrongestBehindTheTiles() {
        let dim = layout.map(of: layout.frame, pointsPerPixel: 2, PanelBackdropLayout.dim)
        #expect(dim.width == 306)
        #expect(dim.height == 216)
        // A tenth of 255.
        #expect(value(dim, of: layout.frame, x: tiles.midX, y: tiles.midY) == 26)
        #expect(value(dim, of: layout.frame, x: layout.frame.minX + 1, y: tiles.midY) == 0)
        // Just under the menu bar, right above the tiles, it is still dark.
        #expect(value(dim, of: layout.frame, x: tiles.midX, y: screen.maxY - 1) > 0)
    }

    @Test func theBlurIsMappedFullBehindTheTilesAndClearAtItsEdge() {
        let blur = layout.map(of: layout.blurFrame, pointsPerPixel: 2, PanelBackdropLayout.blur)
        #expect(blur.width == 225)
        #expect(value(blur, of: layout.blurFrame, x: tiles.midX, y: tiles.midY) == 255)
        // A point inside its edge it has barely begun: 3 parts in 255.
        #expect(value(blur, of: layout.blurFrame, x: layout.blurFrame.minX + 1, y: tiles.midY) == 3)
    }

    @Test func aShortPanelIsStillBlurred() {
        let short = PanelBackdropLayout(tiles: CGRect(x: 1012, y: 1039, width: 360, height: 40), bounds: screen, cornerRadius: 22)
        #expect(!short.blurFrame.isEmpty)
        let blur = short.map(of: short.blurFrame, pointsPerPixel: 2, PanelBackdropLayout.blur)
        #expect(value(blur, of: short.blurFrame, x: short.tiles.midX, y: short.tiles.midY) > 128)
    }
}
