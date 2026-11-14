#if os(macOS)
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
    private static let channelCurves = "curves"

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
    static func makeLayer(points: CGFloat, strength: CGImage, frame: CGRect) -> CALayer? {
        guard isAvailable, let layerClass else { return nil }
        let layer = layerClass.init()
        // Without this the layer only sees its own window, which is empty.
        layer.setValue(true, forKey: "windowServerAware")
        layer.frame = frame

        if filterTypes.contains(variableBlur), let blur = filter(variableBlur) {
            // Measured on macOS 27 with a checkerboard behind the layer: a radius of 1, 1.5 and 2 blurred by
            // 2, 3 and 4 points.
            blur.setValue(points / 2, forKey: "inputRadius")
            blur.setValue(strength, forKey: "inputMaskImage")
            // Otherwise the blur darkens toward the layer's own edges.
            blur.setValue(true, forKey: "inputNormalizeEdges")
            layer.filters = [blur]
        } else if let blur = filter(gaussianBlur) {
            // One strength everywhere, faded out by showing less of it. A radius of 2, 3 and 4 blurred by
            // 1.8, 2.8 and 3.7 points.
            blur.setValue(points * 1.07, forKey: "inputRadius")
            blur.setValue(true, forKey: "inputNormalizeEdges")
            layer.filters = [blur]
            let mask = CALayer()
            mask.frame = layer.bounds
            mask.contents = strength
            mask.magnificationFilter = .linear
            layer.mask = mask
        }
        return layer
    }

    /// A layer that darkens what is bright behind its window, most where it is brightest, faded out by `fade`. Under
    /// a blur layer, the blur takes in what it made. Nil where this system lacks the filter.
    ///
    /// Each colour goes through the same curve, so colours stay colours. The four values are those of a cubic
    /// Bézier, as measured on grey bars on macOS 27: a brightness of x comes out as x - (1 - w) x³. With w = 0.55,
    /// 0.3 comes out as 0.29, a mid grey of 0.5 as 0.44, light grey 0.8 as 0.57 and white as 0.55. The light greys
    /// come out a little lighter than white, which the blur hides. `luminanceCurveMap` takes the same values but
    /// works on brightness alone, and left a grey patch over a coloured desktop picture.
    static func makeCurveLayer(whiteLevel: CGFloat, fade: CGImage, frame: CGRect) -> CALayer? {
        guard isAvailable, filterTypes.contains(channelCurves), let layerClass, let curves = filter(channelCurves) else {
            return nil
        }
        let values = [0, 1.0 / 3, 2.0 / 3, whiteLevel] as [NSNumber]
        curves.setValue(values, forKey: "inputRedValues")
        curves.setValue(values, forKey: "inputGreenValues")
        curves.setValue(values, forKey: "inputBlueValues")
        curves.setValue([0, 1.0 / 3, 2.0 / 3, 1] as [NSNumber], forKey: "inputAlphaValues")
        let layer = layerClass.init()
        layer.setValue(true, forKey: "windowServerAware")
        layer.frame = frame
        layer.filters = [curves]
        let mask = CALayer()
        mask.frame = layer.bounds
        mask.contents = fade
        mask.magnificationFilter = .linear
        layer.mask = mask
        return layer
    }

    private static func filter(_ type: String) -> NSObject? {
        filterClass?.perform(makeFilter, with: type)?.takeUnretainedValue() as? NSObject
    }
}
#endif
