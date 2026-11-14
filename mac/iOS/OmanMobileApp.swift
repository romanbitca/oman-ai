import ClaudeAPI
import OmanCore
import OmanSpeech
import OmanStorage
import OmanSync
import OmanUI
import SwiftUI

@main
struct OmanMobileApp: App {
    @State private var app = MobileApp()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let shell = app.shell {
                MobileRootView(
                    router: shell.router, panel: shell.panel, dictation: shell.dictation, home: shell.home,
                    settings: shell.settings
                )
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { app.cloud?.syncIfStale() }
                }
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
    /// Syncing through iCloud, in a build signed for it.
    private(set) var cloud: CloudSync?

    init() {
        do {
            let database = try OmanDatabase.openDefault()
            let cloud = CloudSync.make(styles: database, actions: database, settings: database)
            let stores: any StyleStore & CustomActionStore & AppSettingsStore = cloud?.stores ?? database
            let services = AppServices(
                writing: WritingRouter(usage: database),
                styles: stores,
                settings: stores,
                apiKeys: KeychainAPIKeyStore(),
                system: MobileSystemBridge(),
                usage: database,
                speech: SpeechService(),
                dictations: database,
                actions: database,
                customActions: stores,
                sync: cloud
            )
            let router = MobileRouter()
            let panel = PanelViewModel(services: services, presenter: router)
            let dictation = DictationController(services: services, presenter: router)
            panel.dictation = dictation
            dictation.panel = panel
            router.panel = panel
            let home = HomeViewModel(services: services)
            let settings = SettingsViewModel(services: services)
            shell = Shell(router: router, panel: panel, dictation: dictation, home: home, settings: settings)
            cloud?.onRemoteChange = {
                panel.reloadChoices()
                settings.reloadSyncedData()
                home.reload()
            }
            cloud?.start()
            self.cloud = cloud
        } catch {
            failure = "Its database couldn't be opened: \(error.localizedDescription)"
        }
    }
}
