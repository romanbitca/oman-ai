import CoreGraphics
import Foundation
import Testing
@testable import SystemBridge

@Suite struct WindowCaptureTests {
    @Test func landscapeIsLimitedByWidth() {
        let size = WindowCapture.scaledSize(width: 3200, height: 2000, maxLongEdge: 1568)
        #expect(size == PixelSize(width: 1568, height: 980))
    }

    @Test func portraitIsLimitedByHeight() {
        let size = WindowCapture.scaledSize(width: 1000, height: 3000, maxLongEdge: 1568)
        #expect(size == PixelSize(width: 523, height: 1568))
    }

    @Test func smallWindowsAreNotEnlarged() {
        let size = WindowCapture.scaledSize(width: 800, height: 600, maxLongEdge: 1568)
        #expect(size == PixelSize(width: 800, height: 600))
    }

    @Test func exactlyAtTheLimitIsUnchanged() {
        let size = WindowCapture.scaledSize(width: 1568, height: 1000, maxLongEdge: 1568)
        #expect(size == PixelSize(width: 1568, height: 1000))
    }

    @Test func fractionalSizesRound() {
        let size = WindowCapture.scaledSize(width: 1000.4, height: 500.6, maxLongEdge: 1568)
        #expect(size == PixelSize(width: 1000, height: 501))
    }

    @Test func extremeAspectRatiosKeepAtLeastOnePixel() {
        let size = WindowCapture.scaledSize(width: 20000, height: 2, maxLongEdge: 1568)
        #expect(size == PixelSize(width: 1568, height: 1))
    }

    private func window(pid: Int32, layer: Int, number: UInt32) -> [String: Any] {
        [
            "kCGWindowOwnerPID": NSNumber(value: pid),
            "kCGWindowLayer": NSNumber(value: layer),
            "kCGWindowNumber": NSNumber(value: number),
        ]
    }

    @Test func picksTheFrontmostNormalWindowOfTheProcess() {
        let windows = [
            window(pid: 7, layer: 0, number: 100),
            window(pid: 42, layer: 25, number: 200),
            window(pid: 42, layer: 0, number: 300),
            window(pid: 42, layer: 0, number: 400),
        ]
        #expect(WindowCapture.frontWindowID(in: windows, ownerProcessID: 42) == 300)
    }

    @Test func invisibleAndTinyWindowsInFrontAreSkipped() {
        var invisible = window(pid: 42, layer: 0, number: 300)
        invisible["kCGWindowAlpha"] = NSNumber(value: 0.0)
        var tooltip = window(pid: 42, layer: 0, number: 400)
        tooltip["kCGWindowAlpha"] = NSNumber(value: 1.0)
        tooltip["kCGWindowBounds"] = ["Width": NSNumber(value: 180), "Height": NSNumber(value: 22)]
        var document = window(pid: 42, layer: 0, number: 500)
        document["kCGWindowAlpha"] = NSNumber(value: 1.0)
        document["kCGWindowBounds"] = ["Width": NSNumber(value: 1200), "Height": NSNumber(value: 800)]

        #expect(WindowCapture.frontWindowID(in: [invisible, tooltip, document], ownerProcessID: 42) == 500)
    }

    @Test func noWindowForTheProcessReturnsNil() {
        let windows = [window(pid: 7, layer: 0, number: 100), window(pid: 42, layer: 25, number: 200)]
        #expect(WindowCapture.frontWindowID(in: windows, ownerProcessID: 42) == nil)
    }

    @Test func encodesJPEG() throws {
        let context = try #require(
            CGContext(
                data: nil,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try #require(context.makeImage())

        let data = try #require(WindowCapture.jpegData(from: image, quality: 0.8))

        #expect(Array(data.prefix(3)) == [0xFF, 0xD8, 0xFF])
    }
}
