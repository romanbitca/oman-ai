import OmanCore
import Testing
@testable import OmanUI

@MainActor
@Suite struct UpdateSettingsTests {
    @Test func reloadShowsTheUpdatersCurrentChoice() {
        let harness = Harness()
        harness.updates.installsUpdatesAutomatically = false
        let model = harness.makeSettings()

        model.reload()

        #expect(model.canUpdate)
        #expect(!model.installsUpdatesAutomatically)
    }

    @Test func changingTheToggleReachesTheUpdater() {
        let harness = Harness()
        let model = harness.makeSettings()
        model.reload()

        model.setInstallsUpdatesAutomatically(false)

        #expect(!harness.updates.installsUpdatesAutomatically)
        #expect(!model.installsUpdatesAutomatically)
    }

    @Test func checkNowAsksTheUpdater() {
        let harness = Harness()
        let model = harness.makeSettings()

        model.checkForUpdates()

        #expect(harness.updates.checkCount == 1)
    }

    @Test func aBuildWithoutAnUpdaterHidesTheControls() {
        let harness = Harness()
        let services = AppServices(
            writing: harness.writing,
            styles: harness.styles,
            settings: harness.settings,
            apiKeys: harness.keys,
            system: harness.system
        )
        let model = SettingsViewModel(services: services)

        model.reload()

        #expect(!model.canUpdate)
        #expect(!model.installsUpdatesAutomatically)
    }
}
