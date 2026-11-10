import AppKit

@main
@MainActor
enum OmanMain {
    private static let delegate = AppDelegate()

    static func main() {
        // AppKit's Password AutoFill check can spin forever walking SwiftUI's key views, freezing the app.
        UserDefaults.standard.register(defaults: ["NSAutoFillHeuristicsEnabled": false])
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
