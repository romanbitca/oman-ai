import AppKit
import SwiftUI
import Testing
@testable import OmanUI

@MainActor
@Suite struct PanelCornerHandleTests {
    private func viewUnderMouse(at topLeftPoint: CGPoint) -> NSView? {
        let side = PanelCornerHandle.side
        let frame = NSRect(x: 0, y: 0, width: side, height: side)
        let host = NSHostingView(rootView: PanelCornerHandle())
        host.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let inHost = NSPoint(x: topLeftPoint.x, y: host.isFlipped ? topLeftPoint.y : side - topLeftPoint.y)
        return host.hitTest(host.convert(inHost, to: host.superview))
    }

    // The curve's centre line, worked out from the same measurements the handle is built from.
    private let thickness = PanelMetrics.gripThickness
    private var radius: CGFloat { PanelMetrics.tileRadius + PanelMetrics.gap + thickness / 2 }
    private var leadIn: CGFloat { PanelCornerHandle.side - thickness - radius }
    private var center: CGPoint {
        CGPoint(x: PanelCornerHandle.side - thickness / 2 - radius, y: thickness / 2 + radius)
    }

    @Test func aClickOnTheMiddleOfTheCurveReachesTheDragView() {
        let reach = radius / 2.0.squareRoot()
        #expect(viewUnderMouse(at: CGPoint(x: center.x + reach, y: center.y - reach)) is WindowDragArea.DragView)
    }

    @Test func aClickAtEitherEndOfTheCurveReachesTheDragView() {
        let start = CGPoint(x: center.x - leadIn, y: center.y - radius)
        let end = CGPoint(x: center.x + radius, y: center.y + leadIn)
        #expect(viewUnderMouse(at: start) is WindowDragArea.DragView)
        #expect(viewUnderMouse(at: end) is WindowDragArea.DragView)
    }
}
