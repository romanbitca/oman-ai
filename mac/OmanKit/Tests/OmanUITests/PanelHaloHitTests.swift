import AppKit
import OmanCore
import SwiftUI
import Testing
@testable import OmanUI

/// The halo closes the panel when clicked, so it must only get clicks that miss the tiles.
@MainActor
@Suite struct PanelHaloHitTests {
    private func viewUnderMouse(at topLeftPoint: CGPoint, pinned: Bool = false) -> NSView? {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: SelectionCapture(app: Harness.slack, text: "hey"))
        if pinned {
            model.togglePin()
        }
        let size = PanelRootView.windowSize
        let frame = NSRect(origin: .zero, size: size)
        let host = NSHostingView(rootView: PanelRootView(model: model))
        host.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let inHost = NSPoint(x: topLeftPoint.x, y: host.isFlipped ? topLeftPoint.y : size.height - topLeftPoint.y)
        return host.hitTest(host.convert(inHost, to: host.superview))
    }

    private let tilesLeft = PanelMetrics.sideMargin

    @Test func aClickOnAnEmptyPartOfATileStaysWithTheTile() {
        // The header tile, between its text and its buttons.
        #expect(!(viewUnderMouse(at: CGPoint(x: tilesLeft + 220, y: 22)) is PanelHalo.HaloView))
    }

    @Test func aClickJustOutsideTheTilesReachesTheHalo() {
        #expect(viewUnderMouse(at: CGPoint(x: tilesLeft - 10, y: 30)) is PanelHalo.HaloView)
    }

    @Test func aPinnedPanelHasNoHalo() {
        #expect(!(viewUnderMouse(at: CGPoint(x: tilesLeft - 10, y: 60), pinned: true) is PanelHalo.HaloView))
    }
}
