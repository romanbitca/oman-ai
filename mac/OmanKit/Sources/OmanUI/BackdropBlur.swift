import AppKit
import QuartzCore

/// Core Animation's own blur of whatever is behind a window: no tint, and a strength that can change from
/// spot to spot, so it fades out instead of ending at a line.
///
/// macOS has no public call for this. Its materials and glass all tint what they blur, which made earlier
/// backdrops look like a box behind the panel. This is the layer AppKit builds its own materials on, with
/// nothing on it but a blur. Its classes are looked up at run time, so if a future macOS drops them nothing
/// breaks: the panel goes back to frosted glass with no backdrop.
@MainActor
enum BackdropBlur {
    private static let layerClass = NSClassFromString("CABackdropLayer") as? CALayer.Type
    private static let filterClass = NSClassFromString("CAFilter") as? NSObject.Type
    private static let makeFilter = NSSelectorFromString("filterWithType:")
    private static let variableBlur = "variableBlur"
    private static let gaussianBlur = "gaussianBlur"
    private static let luminanceCurve = "luminanceCurveMap"

    /// Whether this system can darken only what is bright behind a window.
    static var canPressBrightness: Bool { isAvailable && filterTypes.contains(luminanceCurve) }

    /// The filters this system has. Asking for one it doesn't have still returns an object, which does nothing.
    private static let filterTypes: [String] = {
        let selector = NSSelectorFromString("filterTypes")
        guard let filterClass, filterClass.responds(to: selector) else { return [] }
        return filterClass.perform(selector)?.takeUnretainedValue() as? [String] ?? []
    }()

    static var isAvailable: Bool {
        guard let layerClass, filterClass?.responds(to: makeFilter) == true else { return false }
        return layerClass.instancesRespond(to: NSSelectorFromString("setWindowServerAware:"))
            && (filterTypes.contains(variableBlur) || filterTypes.contains(gaussianBlur))
    }

    /// A layer over `frame` that shows what is behind its window, blurred by `points` where `strength` is
    /// opaque, less where it is fainter, and not at all where it is clear.
    ///
    /// With `ceiling` below 1, what is brighter than about half is pressed down toward that brightness, and what is
    /// darker is left as it is: white words stay readable over a white window, and nothing shows over a dark one.
    static func makeLayer(points: CGFloat, strength: CGImage, frame: CGRect, ceiling: CGFloat = 1) -> CALayer? {
        guard isAvailable, let layerClass else { return nil }
        let layer = layerClass.init()
        // Without this the layer only sees its own window, which is empty.
        layer.setValue(true, forKey: "windowServerAware")
        layer.frame = frame
        var filters: [NSObject] = []
        var fadesAsAWhole = false

        if points > 0, filterTypes.contains(variableBlur), let blur = filter(variableBlur) {
            // Measured on macOS 27 with a checkerboard behind the layer: a radius of 1, 1.5 and 2 blurred by
            // 2, 3 and 4 points.
            blur.setValue(points / 2, forKey: "inputRadius")
            blur.setValue(strength, forKey: "inputMaskImage")
            // Otherwise the blur darkens toward the layer's own edges.
            blur.setValue(true, forKey: "inputNormalizeEdges")
            filters.append(blur)
        } else if points > 0, let blur = filter(gaussianBlur) {
            // One strength everywhere, faded out by showing less of it. A radius of 2, 3 and 4 blurred by
            // 1.8, 2.8 and 3.7 points.
            blur.setValue(points * 1.07, forKey: "inputRadius")
            blur.setValue(true, forKey: "inputNormalizeEdges")
            filters.append(blur)
            fadesAsAWhole = true
        }
        if ceiling < 1, filterTypes.contains(luminanceCurve), let curve = filter(luminanceCurve) {
            // The brightness that comes out for none, a third, two thirds and all of what goes in.
            curve.setValue([0, 0.33, min(0.6, ceiling), ceiling] as [NSNumber], forKey: "inputValues")
            curve.setValue(1, forKey: "inputAmount")
            filters.append(curve)
            // The curve has no fade of its own.
            fadesAsAWhole = true
        }
        guard !filters.isEmpty else { return nil }
        layer.filters = filters
        if fadesAsAWhole {
            let mask = CALayer()
            mask.frame = layer.bounds
            mask.contents = strength
            mask.magnificationFilter = .linear
            layer.mask = mask
        }
        return layer
    }

    private static func filter(_ type: String) -> NSObject? {
        filterClass?.perform(makeFilter, with: type)?.takeUnretainedValue() as? NSObject
    }
}
