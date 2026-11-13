import OmanCore

/// How the model groups are named and explained, on the Mac's Settings and the iPhone's.
extension DictationModel.Group {
    var title: String {
        switch self {
        case .live: "Live"
        case .accurate: "Accurate"
        case .small: "Small"
        }
    }

    var explanation: String {
        switch self {
        case .live: "Your words appear while you speak."
        case .accurate: "Your words follow a moment later, read again as you go, which makes them more accurate."
        case .small: "Smaller downloads, for a Mac short on space."
        }
    }
}
