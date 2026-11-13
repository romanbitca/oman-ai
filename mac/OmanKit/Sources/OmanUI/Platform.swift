#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import SwiftUI

#if canImport(AppKit)
typealias PlatformImage = NSImage
typealias PlatformFont = NSFont
#else
typealias PlatformImage = UIImage
typealias PlatformFont = UIFont
#endif

extension Image {
    init(platformImage image: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: image)
        #else
        self.init(uiImage: image)
        #endif
    }
}

/// What the Mac and the iPhone do differently, behind one name, so the views that share them say it once.
@MainActor
enum Platform {
    /// Posted when OmanAI comes to the front again, so counts and lists can be read afresh.
    static var didBecomeActive: Notification.Name {
        #if canImport(AppKit)
        NSApplication.didBecomeActiveNotification
        #else
        UIApplication.didBecomeActiveNotification
        #endif
    }

    /// An app's icon by its bundle identifier, where the system can say. The iPhone can't show other apps' icons.
    static func appIcon(bundleID: String) -> PlatformImage? {
        #if canImport(AppKit)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
        #else
        return nil
        #endif
    }

    /// An app's icon from where it is installed. Nil on the iPhone.
    static func appIcon(at url: URL) -> PlatformImage? {
        #if canImport(AppKit)
        return NSWorkspace.shared.icon(forFile: url.path)
        #else
        return nil
        #endif
    }

    /// Asks before something that can't be undone, and runs `confirmed` only on a yes. On the Mac the question waits in
    /// a dialog, as before; on the iPhone it comes up as an alert over the app.
    static func confirm(
        _ title: String, detail: String, action: String = "Delete", confirmed: @escaping @MainActor () -> Void
    ) {
        #if canImport(AppKit)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: action).hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn { confirmed() }
        #else
        let alert = UIAlertController(title: title, message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: action, style: .destructive) { _ in
            MainActor.assumeIsolated { confirmed() }
        })
        topViewController()?.present(alert, animated: true)
        #endif
    }

    #if !canImport(AppKit)
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = scenes.flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    #endif
}
