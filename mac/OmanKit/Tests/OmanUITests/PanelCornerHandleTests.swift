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

    @Test func aClickOnTheMiddleOfTheCurveReachesTheDragView() {
        #expect(viewUnderMouse(at: CGPoint(x: 39.46, y: 16.54)) is WindowDragArea.DragView)
    }

    @Test func aClickAtEitherEndOfTheCurveReachesTheDragView() {
        #expect(viewUnderMouse(at: CGPoint(x: 6, y: 6)) is WindowDragArea.DragView)
        #expect(viewUnderMouse(at: CGPoint(x: 50, y: 50)) is WindowDragArea.DragView)
    }
}
