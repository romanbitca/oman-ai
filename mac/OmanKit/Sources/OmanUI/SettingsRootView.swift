import SwiftUI

public struct SettingsRootView: View {
    private let model: SettingsViewModel

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            StylesSettingsView(model: model)
                .tabItem { Label("Styles", systemImage: "text.quote") }
        }
        .frame(width: 720, height: 520)
    }
}
