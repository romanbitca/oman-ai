import AppKit
import ClaudeAPI
import OmanCore
import OmanSpeech
import OmanStorage
import SystemBridge

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: MenuBarCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        do {
            let database = try OmanDatabase.openDefault()
            let services = AppServices(
                writing: WritingRouter(usage: database),
                styles: database,
                settings: database,
                apiKeys: KeychainAPIKeyStore(),
                system: MacSystemBridge(),
                updates: UpdaterController.makeIfConfigured(),
                usage: database,
                speech: SpeechService(),
                dictations: database,
                actions: database
            )
            coordinator = MenuBarCoordinator(services: services)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "OmanAI couldn't open its database."
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// Opening OmanAI while it runs shows its own window. Without this, macOS would bring back the Settings window, which
    /// is kept after it closes.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.openHome()
        return false
    }

    // Text fields in a normal window only get Cmd+V and the other editing shortcuts through an Edit menu.
    private func installMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit OmanAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }
}
