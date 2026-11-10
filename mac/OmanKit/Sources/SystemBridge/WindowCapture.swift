import CoreGraphics
import Foundation
import ImageIO
import OmanCore
import ScreenCaptureKit
import UniformTypeIdentifiers

enum WindowCaptureError: LocalizedError, Equatable {
    case permissionMissing
    case windowNotFound
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionMissing:
            "OmanAI needs Screen Recording permission to include the screen."
        case .windowNotFound:
            "Couldn't find the window you're writing in."
        case .encodingFailed:
            "Couldn't prepare the screenshot."
        }
    }
}

struct PixelSize: Equatable {
    let width: Int
    let height: Int
}

enum WindowCapture {
    private static let maxLongEdgePixels = 1568
    private static let jpegQuality = 0.8

    static func captureFrontWindow(ofProcess processID: pid_t) async throws -> ScreenshotAttachment {
        guard CGPreflightScreenCaptureAccess() else { throw WindowCaptureError.permissionMissing }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        guard let windowID = frontWindowID(in: windowList, ownerProcessID: processID) else {
            throw WindowCaptureError.windowNotFound
        }

        let content = try await SCShareableContent.current
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw WindowCaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = Double(filter.pointPixelScale)
        let size = scaledSize(
            width: window.frame.width * scale,
            height: window.frame.height * scale,
            maxLongEdge: maxLongEdgePixels
        )

        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        guard let jpeg = jpegData(from: image, quality: jpegQuality) else {
            throw WindowCaptureError.encodingFailed
        }
        return ScreenshotAttachment(jpegData: jpeg, pixelWidth: image.width, pixelHeight: image.height)
    }

    /// `windows` must be front to back, as `CGWindowListCopyWindowInfo` returns them.
    static func frontWindowID(in windows: [[String: Any]], ownerProcessID: pid_t) -> CGWindowID? {
        for window in windows {
            guard window["kCGWindowOwnerPID"] as? pid_t == ownerProcessID,
                  window["kCGWindowLayer"] as? Int == 0,
                  let windowID = window["kCGWindowNumber"] as? CGWindowID
            else {
                continue
            }
            return windowID
        }
        return nil
    }

    static func scaledSize(width: Double, height: Double, maxLongEdge: Int) -> PixelSize {
        let longEdge = max(width, height)
        let factor = longEdge > Double(maxLongEdge) ? Double(maxLongEdge) / longEdge : 1
        return PixelSize(
            width: max(1, Int((width * factor).rounded())),
            height: max(1, Int((height * factor).rounded()))
        )
    }

    static func jpegData(from image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let properties = [kCGImageDestinationLossyCompressionQuality as String: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
