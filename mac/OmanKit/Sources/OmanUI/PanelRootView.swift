import Observation
import OmanCore
import SwiftUI

@MainActor
@Observable
public final class PanelViewModel {
    private let services: AppServices
    private weak var presenter: (any PanelPresenting)?
    var capture = SelectionCapture(app: nil, text: nil)

    public init(services: AppServices, presenter: any PanelPresenting) {
        self.services = services
        self.presenter = presenter
    }

    public func begin(with capture: SelectionCapture) {
        self.capture = capture
    }

    public func panelDidClose() {}
}

public struct PanelRootView: View {
    private let model: PanelViewModel

    public init(model: PanelViewModel) {
        self.model = model
    }

    public var body: some View {
        Text(model.capture.text ?? "Nothing selected")
            .padding()
            .frame(width: 360)
    }
}

@MainActor
@Observable
public final class SettingsViewModel {
    private let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public func reload() {}
}

public struct SettingsRootView: View {
    private let model: SettingsViewModel

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        Text("Settings").frame(width: 720, height: 520)
    }
}
