import OmanCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        SettingsTile(title: "Startup") {
            SettingsToggleRow(
                title: "Open at login",
                detail: "Keeps OmanAI ready in your menu bar after a restart.",
                isOn: Binding(get: { model.isLaunchAtLogin }, set: { model.setLaunchAtLogin($0) })
            )
            if let error = model.launchAtLoginError {
                NoticeText(text: error)
            }
        }

        SettingsTile(title: "Appearance") {
            SettingsRow(title: "Theme", detail: "Applies to the panel and this window.") {
                LiquidSegmented(
                    options: AppearanceMode.allCases,
                    selection: model.preferences.appearance,
                    title: \.displayName,
                    onSelect: { model.setAppearance($0) }
                )
            }
        }

        SettingsTile(title: "Panel") {
            SettingsToggleRow(
                title: "Keep open when I click elsewhere",
                detail: "Starts every panel pinned, so you can copy from other apps.",
                isOn: Binding(
                    get: { model.preferences.keepsPanelOpen },
                    set: { value in model.updatePreferences { $0.keepsPanelOpen = value } }
                )
            )
            Divider()
            SettingsToggleRow(
                title: "Include the screen by default",
                detail: "Sends a picture of the window you're writing in with each request.",
                isOn: Binding(
                    get: { model.preferences.includesScreenByDefault },
                    set: { value in model.updatePreferences { $0.includesScreenByDefault = value } }
                )
            )
        }

        if let error = model.preferencesError {
            NoticeText(text: error).padding(.horizontal, 6)
        }
    }
}
