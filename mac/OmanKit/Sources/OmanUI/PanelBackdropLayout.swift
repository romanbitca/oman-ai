import CoreGraphics

/// Where the panel's dimmed, blurred backdrop goes, as behind Control Center: a band from the screen edge
/// nearest the panel, at full strength behind the tiles and fading out beyond them.
public struct PanelBackdropLayout: Equatable {
    /// Full strength from the screen edge to this far past the tiles.
    static let clearance: CGFloat = 60
    /// Then the effect fades out over this distance.
    static let fade: CGFloat = 280
    /// The band covers at least this share of the screen's width, so a panel near the edge still sits in a wide band.
    static let minimumShare: CGFloat = 0.42

    /// The band, in screen coordinates.
    public let frame: CGRect
    /// True when the band starts at the right edge of the screen and fades out to the left.
    public let isAnchoredRight: Bool
    /// The share of the band's width, from its open side, over which it fades in.
    public let fadeFraction: CGFloat

    /// `screen` is the screen's whole frame, `menuBarBottom` where the menu bar ends, and `tiles` the panel's glass.
    public init(screen: CGRect, menuBarBottom: CGFloat, tiles: CGRect) {
        isAnchoredRight = tiles.midX >= screen.midX
        let reachToTiles = isAnchoredRight ? screen.maxX - tiles.minX : tiles.maxX - screen.minX
        let width = min(screen.width, max(screen.width * Self.minimumShare, reachToTiles + Self.clearance + Self.fade))
        let originX = isAnchoredRight ? screen.maxX - width : screen.minX
        frame = CGRect(x: originX, y: screen.minY, width: width, height: max(0, menuBarBottom - screen.minY))
        fadeFraction = width > 0 ? min(1, Self.fade / width) : 1
    }
}
