#if os(iOS)
import OmanCore
import SwiftUI

/// The iPhone app: the Mac's panel to write with, a microphone to dictate with, what OmanAI did for the person, and
/// Settings, each in a tab.
public struct MobileRootView: View {
    @Bindable var router: MobileRouter
    let panel: PanelViewModel
    let dictation: DictationController
    let home: HomeViewModel
    let settings: SettingsViewModel

    public init(
        router: MobileRouter, panel: PanelViewModel, dictation: DictationController, home: HomeViewModel,
        settings: SettingsViewModel
    ) {
        self.router = router
        self.panel = panel
        self.dictation = dictation
        self.home = home
        self.settings = settings
    }

    public var body: some View {
        TabView(selection: $router.tab) {
            Tab("Write", systemImage: "square.and.pencil", value: MobileRouter.Tab.write) {
                MobilePanelScreen(model: panel)
            }
            Tab("Dictate", systemImage: "waveform", value: MobileRouter.Tab.dictate) {
                MobileDictationScreen(controller: dictation, router: router)
            }
            Tab("Home", systemImage: "chart.line.uptrend.xyaxis", value: MobileRouter.Tab.home) {
                MobileHomeScreen(model: home)
            }
            Tab("Settings", systemImage: "gearshape", value: MobileRouter.Tab.settings) {
                MobileSettingsScreen(model: settings)
            }
        }
        .tint(MobilePalette.accent)
        .onChange(of: router.tab) { _, tab in
            switch tab {
            case .home: home.reload()
            case .settings: settings.reload()
            case .write: panel.reloadChoices()
            case .dictate: break
            }
        }
    }
}

enum MobilePalette {
    /// OmanAI's blue, from the app's icon.
    static let accent = Color(red: 0.29, green: 0.47, blue: 0.86)
}

/// The Mac's panel, screen for screen, at the width of the phone.
struct MobilePanelScreen: View {
    @Bindable var model: PanelViewModel
    @Namespace private var space

    var body: some View {
        ZStack(alignment: .top) {
            MobileBackground()
            content
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .environment(\.liquidSpace, space)
        .environment(\.panelIsFloating, false)
        .environment(\.liquidClearGlass, false)
        .environment(\.liquidColorBoost, Liquid.colorBoost(usesClearGlass: false))
        .animation(Liquid.morph, value: model.screen)
        .withoutSystemWritingTools()
        .onAppear {
            if model.session == 0 { model.begin(with: SelectionCapture(app: nil, text: nil)) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .setup: PanelSetupView(model: model).transition(Liquid.swap)
        case .home: PanelHomeView(model: model).transition(Liquid.swap)
        case .compose: PanelComposeView(model: model).transition(Liquid.swap)
        case .working: PanelWorkingView(model: model).transition(Liquid.swap)
        case .result: PanelResultView(model: model).transition(Liquid.swap)
        case .failed: PanelFailedView(model: model).transition(Liquid.swap)
        }
    }
}
#endif
