import AppKit
import Foundation
import OmanCore
import Sparkle

/// Keeps OmanAI up to date from the feed in Info.plist.
@MainActor
final class UpdaterController: NSObject, AppUpdating, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    /// Only release builds get a public key, so local builds and forks never update themselves.
    static func makeIfConfigured() -> UpdaterController? {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        guard let key, !key.isEmpty else { return nil }
        let updater = UpdaterController()
        updater.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: updater
        )
        return updater
    }

    var installsUpdatesAutomatically: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { controller?.updater.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        // A menu bar app is never active by itself, and Sparkle's window would open behind other apps.
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    // Sparkle asks menu bar apps to opt in. Its own alert is the reminder, since there is no Dock icon to badge.
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
