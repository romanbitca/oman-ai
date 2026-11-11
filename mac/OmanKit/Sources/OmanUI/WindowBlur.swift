import AppKit

/// The window server's own blur of whatever is behind a window, with no tint and at any strength.
///
/// macOS has no public call for this. Its materials and glass all tint what they blur, which made earlier
/// backdrops look like a box behind the panel. This is the call that terminal apps such as iTerm2 and Ghostty use
/// for see-through windows. It is looked up at run time, so if a future macOS drops it nothing breaks: the panel
/// goes back to frosted glass with no backdrop.
@MainActor
enum WindowBlur {
    private typealias SetRadius = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias Connection = @convention(c) () -> Int32

    private static let handle = dlopen(nil, RTLD_NOW)
    private static let setRadius = dlsym(handle, "CGSSetWindowBackgroundBlurRadius")
        .map { unsafeBitCast($0, to: SetRadius.self) }
    private static let connection = dlsym(handle, "CGSDefaultConnectionForThread")
        .map { unsafeBitCast($0, to: Connection.self) }

    static var isAvailable: Bool { setRadius != nil && connection != nil }

    /// Three units of radius blur by about one point. The blur only shows where the window's own pixels are not
    /// fully clear, and it is all or nothing there: an alpha of 2/255 is enough, 1/255 is not.
    @discardableResult
    static func set(radius: Int32, for window: NSWindow) -> Bool {
        guard let setRadius, let connection, window.windowNumber > 0 else { return false }
        return setRadius(connection(), Int32(window.windowNumber), radius) == 0
    }
}
