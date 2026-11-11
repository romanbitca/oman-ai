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

@Suite struct PanelBackdropLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    private let tiles = CGRect(x: 1012, y: 779, width: 360, height: 300)
    private var layout: PanelBackdropLayout { PanelBackdropLayout(tiles: tiles, bounds: screen, cornerRadius: 22) }

    @Test func theBlurStepsAddUpToControlCentersThreePoints() {
        // Three units of radius blur by one point, and stacked blurs add as the root of the sum of squares.
        let total = PanelBackdropLayout.blurSteps.map { pow(Double($0.radius) / 3, 2) }.reduce(0, +).squareRoot()
        #expect(abs(total - 3) < 0.15)
    }

    @Test func theStepsNestFromTheOutsideIn() {
        let frames = PanelBackdropLayout.blurSteps.map { layout.frame(for: $0) }
        for (outer, inner) in zip(frames, frames.dropFirst()) {
            #expect(outer.contains(inner))
            #expect(outer != inner)
        }
        #expect(layout.shape(for: PanelBackdropLayout.blurSteps[0]).cornerRadius == 53)
        #expect(layout.shape(for: PanelBackdropLayout.blurSteps[5]).cornerRadius == 0)
    }

    @Test func theDarkeningIsFullBehindTheTilesAndGoneFarFromThem() {
        #expect(PanelBackdropLayout.dim(atDistance: -100) == 0.10)
        #expect(PanelBackdropLayout.dim(atDistance: -34) == 0.10)
        #expect(abs(PanelBackdropLayout.dim(atDistance: 46) - 0.05) < 1e-9)
        #expect(PanelBackdropLayout.dim(atDistance: 126) == 0)
        #expect(PanelBackdropLayout.dim(atDistance: 300) == 0)
    }

    @Test(arguments: [-60.0, -30, -5, 8, 20, 40, 90])
    func theDimLayerAndTheBlurFillsTogetherGiveTheMeasuredDarkening(distance: Double) {
        let fills = PanelBackdropLayout.blurSteps.filter { distance <= $0.outset }.count
        let layer = PanelBackdropLayout.dimLayerAlpha(atDistance: distance)
        let total = 1 - (1 - layer) * pow(1 - 3.0 / 255, Double(fills))
        #expect(abs(total - PanelBackdropLayout.dim(atDistance: distance)) < 1e-9)
    }

    @Test func nothingIsDrawnOverTheMenuBar() {
        // The panel hangs 5 points under the menu bar, so every part of the backdrop is cut off there.
        #expect(layout.dimFrame.maxY == screen.maxY)
        #expect(layout.dimFrame == CGRect(x: 886, y: 653, width: 612, height: 431))
        for step in PanelBackdropLayout.blurSteps {
            #expect(layout.frame(for: step).maxY <= screen.maxY)
        }
    }

    @Test func distanceFollowsTheTilesRoundedOutline() {
        #expect(layout.distance(to: CGPoint(x: tiles.midX, y: tiles.midY)) == -150)
        #expect(abs(layout.distance(to: CGPoint(x: tiles.minX, y: tiles.midY))) < 1e-9)
        #expect(abs(layout.distance(to: CGPoint(x: tiles.minX - 40, y: tiles.midY)) - 40) < 1e-9)
        // The square corner of the tiles' frame is outside their rounded corner.
        let corner = layout.distance(to: CGPoint(x: tiles.minX, y: tiles.minY))
        #expect(abs(corner - (22 * 2.0.squareRoot() - 22)) < 1e-9)
    }

    @Test func aShortPanelStillLeavesEveryStepSomethingToBlur() {
        let short = PanelBackdropLayout(tiles: CGRect(x: 1012, y: 1039, width: 360, height: 40), bounds: screen, cornerRadius: 22)
        for step in PanelBackdropLayout.blurSteps {
            let frame = short.frame(for: step)
            #expect(frame.width > 0)
            #expect(frame.height > 0)
        }
    }

    @Test func theDimLayerIsDrawnTopRowFirstAndDarkestBehindTheTiles() {
        let dim = layout.dimPixels(pointsPerPixel: 2)
        #expect(dim.width == 306)
        #expect(dim.height == 216)
        func alpha(x: CGFloat, y: CGFloat) -> UInt8 {
            let column = Int((x - layout.dimFrame.minX) / 2)
            let row = Int((layout.dimFrame.maxY - y) / 2)
            return dim.pixels[(row * dim.width + column) * 4 + 3]
        }
        // Behind the tiles all six blur fills are in front, so the layer itself adds the rest of the 10%.
        let behindTiles = UInt8((PanelBackdropLayout.dimLayerAlpha(atDistance: -150) * 255).rounded())
        #expect(alpha(x: tiles.midX, y: tiles.midY) == behindTiles)
        #expect(alpha(x: layout.dimFrame.minX + 1, y: tiles.midY) == 0)
        // Just under the menu bar, right above the tiles, it is still dark.
        #expect(alpha(x: tiles.midX, y: screen.maxY - 1) > 0)
    }
}
