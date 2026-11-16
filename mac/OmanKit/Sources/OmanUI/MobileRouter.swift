#if os(iOS)
import OmanCore
import SwiftUI

/// The iPhone app's tabs, and what the shared models ask the app to do: show the panel, open Settings, or open words
/// just dictated in the panel. The Mac does these with windows and a menu bar icon.
@MainActor
@Observable
public final class MobileRouter: PanelPresenting, DictationPresenting {
    public enum Tab: Hashable, Sendable {
        case write, dictate, home, settings
    }

    public var tab: Tab = .write
    @ObservationIgnored public weak var panel: PanelViewModel?

    public init() {}

    // MARK: PanelPresenting

    public func hidePanel() {}
    public func showPanel() { tab = .write }
    public func setPanelPinned(_ pinned: Bool) {}
    public func setPanelContentHeight(_ height: CGFloat) {}
    public func openSettings() { tab = .settings }

    // MARK: DictationPresenting

    public func showDictationPill(at position: DictationPillPosition) {}
    public func hideDictationPill() {}
    public func setDictationActive(_ active: Bool) {}

    public func showPanel(withDictatedText text: String, from app: SourceApp?) {
        panel?.begin(withDictatedText: text, from: nil)
        tab = .write
    }

    /// Opens the panel on these words and runs one of its actions on them at once.
    func open(_ text: String, then action: ((PanelViewModel) -> Void)? = nil) {
        guard let panel else { return }
        panel.begin(withDictatedText: text, from: nil)
        tab = .write
        action?(panel)
    }
}

/// OmanAI's soft colours behind the glass, as on the website: teal, blue and violet over a light or a dark page.
struct MobileBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let isDark = scheme == .dark
        ZStack {
            (isDark ? Color(red: 0.05, green: 0.07, blue: 0.11) : Color(red: 0.95, green: 0.96, blue: 0.98))
            RadialGradient(
                colors: [Color(red: 0.31, green: 0.82, blue: 0.71).opacity(isDark ? 0.34 : 0.42), .clear],
                center: .topLeading, startRadius: 0, endRadius: 440
            )
            RadialGradient(
                colors: [Color(red: 0.36, green: 0.58, blue: 1).opacity(isDark ? 0.3 : 0.26), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 380
            )
            RadialGradient(
                colors: [Color(red: 0.6, green: 0.46, blue: 1).opacity(isDark ? 0.34 : 0.3), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}
#endif
