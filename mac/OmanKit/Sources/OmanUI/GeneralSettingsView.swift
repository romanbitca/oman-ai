import AppKit
import OmanCore
import SwiftUI

struct GeneralSettingsView: View {
    let model: SettingsViewModel

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        SettingsForm {
            Section {
                Toggle(isOn: Binding(get: { model.isLaunchAtLogin }, set: { model.setLaunchAtLogin($0) })) {
                    Text("Open at login")
                    Text("Keeps OmanAI ready in your menu bar after a restart.")
                }
                if let error = model.launchAtLoginError {
                    SettingsError(text: error)
                }
                Picker(selection: Binding(get: { model.preferences.appearance }, set: { model.setAppearance($0) })) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    Text("Theme")
                    Text("Applies to the panel and this window.")
                }
            }

            Section("Panel") {
                Toggle(isOn: model.preference(\.keepsPanelOpen)) {
                    Text("Keep open when I click elsewhere")
                    Text("Starts every panel pinned, so you can copy from other apps.")
                }
                Toggle(isOn: model.preference(\.includesScreenByDefault)) {
                    Text("Include the screen by default")
                    Text("Sends a picture of the window you're writing in with each request.")
                }
                if let error = model.preferencesError {
                    SettingsError(text: error)
                }
            }

            if model.canUpdate {
                Section("Updates") {
                    Toggle(
                        isOn: Binding(
                            get: { model.installsUpdatesAutomatically },
                            set: { model.setInstallsUpdatesAutomatically($0) }
                        )
                    ) {
                        Text("Install updates automatically")
                        Text("Checks GitHub once a day and installs new versions when OmanAI quits.")
                    }
                    LabeledContent("Check for a new version") {
                        Button("Check Now") { model.checkForUpdates() }
                    }
                }
            }

            Section {
                LabeledContent {
                    Button("View on GitHub") {
                        if let url = URL(string: "https://github.com/romanbitca/oman-ai") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: {
                    Text("OmanAI")
                    Text("\(version). Open source, free to use and change under the MIT license.")
                }
                LabeledContent {
                    Button("Quit") { NSApp.terminate(nil) }
                } label: {
                    Text("Quit OmanAI")
                    Text("The menu bar icon goes away until you open the app again.")
                }
            }
        }
    }
}
