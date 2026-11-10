import AppKit
import ClaudeAPI
import OmanCore
import OmanStorage
import SystemBridge

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: MenuBarCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let database = try OmanDatabase.openDefault()
            let services = AppServices(
                writing: ClaudeClient(),
                styles: database,
                settings: database,
                apiKeys: KeychainAPIKeyStore(),
                system: MacSystemBridge()
            )
            coordinator = MenuBarCoordinator(services: services)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "oman couldn't open its database."
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}
