import ClaudeAPI
import OmanCore
import OmanSpeech
import OmanStorage
import OmanUI
import SwiftUI

@main
struct OmanMobileApp: App {
    @State private var app = MobileApp()

    var body: some Scene {
        WindowGroup {
            if let shell = app.shell {
                MobileRootView(
                    router: shell.router, panel: shell.panel, dictation: shell.dictation, home: shell.home,
                    settings: shell.settings
                )
            } else {
                ContentUnavailableView(
                    "OmanAI couldn't start",
                    systemImage: "exclamationmark.triangle",
                    description: Text(app.failure ?? "")
                )
            }
        }
    }
}

/// The same services and models as the Mac's, with the iPhone's own way to reach the system.
@MainActor
@Observable
final class MobileApp {
    struct Shell {
        let router: MobileRouter
        let panel: PanelViewModel
        let dictation: DictationController
        let home: HomeViewModel
        let settings: SettingsViewModel
    }

    private(set) var shell: Shell?
    private(set) var failure: String?

    init() {
        do {
            let database = try OmanDatabase.openDefault()
            let services = AppServices(
                writing: WritingRouter(usage: database),
                styles: database,
                settings: database,
                apiKeys: KeychainAPIKeyStore(),
                system: MobileSystemBridge(),
                usage: database,
                speech: SpeechService(),
                dictations: database,
                actions: database,
                customActions: database
            )
            let router = MobileRouter()
            let panel = PanelViewModel(services: services, presenter: router)
            let dictation = DictationController(services: services, presenter: router)
            panel.dictation = dictation
            dictation.panel = panel
            router.panel = panel
            shell = Shell(
                router: router, panel: panel, dictation: dictation, home: HomeViewModel(services: services),
                settings: SettingsViewModel(services: services)
            )
        } catch {
            failure = "Its database couldn't be opened: \(error.localizedDescription)"
        }
    }
}
