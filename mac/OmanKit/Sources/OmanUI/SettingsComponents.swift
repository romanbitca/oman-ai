import OmanCore
import SwiftUI

enum SettingsMetrics {
    /// Every page is this wide, as in Safari's or Mail's settings. Only the window's height follows the page.
    static let width: CGFloat = 600
    static let minPageHeight: CGFloat = 200
    /// A page taller than this scrolls, so the window stays on the screen.
    static let maxPageHeight: CGFloat = 620
    static let resizeDuration: TimeInterval = 0.2
}

/// How tall a page may get, and where it says how tall it is.
struct SettingsPageSizing: Sendable {
    var maxHeight = SettingsMetrics.maxPageHeight
    var report: @MainActor (CGFloat) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var settingsPageSizing = SettingsPageSizing()
}

/// One page of Settings, in macOS's own grouped form.
struct SettingsForm<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.settingsPageSizing) private var sizing
    @State private var scrollsAlways = false

    var body: some View {
        // The page hangs from the top of whatever height the window has at that moment and is laid out at its
        // own height, so it stays still while the window grows or shrinks around it.
        Color.clear.overlay(alignment: .top) {
            ViewThatFits(in: .vertical) {
                if !scrollsAlways {
                    form.fixedSize(horizontal: false, vertical: true)
                }
                form
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // A grouped form is as tall as what it holds. Should a version of macOS say it is next to
                // nothing, the page would be cut off, so it scrolls at full height from then on instead.
                if height < SettingsMetrics.minPageHeight / 2 {
                    scrollsAlways = true
                } else {
                    sizing.report(height)
                }
            }
            .frame(width: SettingsMetrics.width, height: sizing.maxHeight, alignment: .top)
        }
        .withoutSystemWritingTools()
    }

    private var form: some View {
        Form { content }.formStyle(.grouped)
    }
}

/// Something that went wrong, in the row under the control it belongs to.
struct SettingsError: View {
    let text: String

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension SettingsViewModel {
    /// A control's link to one preference, which is saved on every change.
    func preference<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value> & Sendable) -> Binding<Value> {
        Binding(
            get: { self.preferences[keyPath: keyPath] },
            set: { value in self.updatePreferences { $0[keyPath: keyPath] = value } }
        )
    }
}
