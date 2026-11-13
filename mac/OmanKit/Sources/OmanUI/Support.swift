import Foundation
import OmanCore

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension WritingStyle {
    var displayName: String { name.trimmed.isEmpty ? "Untitled" : name }
}

extension CustomAction {
    var displayName: String { name.trimmed.isEmpty ? "Untitled" : name }
}

extension WritingModel {
    var tagline: String {
        switch self {
        case .haiku: "Fastest and cheapest"
        case .sonnet: "Balanced"
        case .opus: "Most capable"
        case .appleOnDevice: "Free, stays on this Mac"
        }
    }
}
