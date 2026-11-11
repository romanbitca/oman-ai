import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, writing, styles, shortcuts, access, spending, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .writing: "Writing"
        case .styles: "Styles"
        case .shortcuts: "Shortcuts"
        case .access: "Key & Access"
        case .spending: "Spending"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .writing: "text.cursor"
        case .styles: "quote.opening"
        case .shortcuts: "command"
        case .access: "key"
        case .spending: "chart.bar"
        case .about: "info.circle"
        }
    }
}

public struct SettingsRootView: View {
    public static let windowSize = CGSize(width: 880, height: 640)

    private let model: SettingsViewModel
    @State private var page: SettingsPage = .general

    public init(model: SettingsViewModel) {
        self.model = model
    }

    public var body: some View {
        LiquidContainer(spacing: 6) {
            HStack(alignment: .top, spacing: SettingsMetrics.gap) {
                navigation
                content
            }
            .padding(SettingsMetrics.outer)
        }
        .environment(\.liquidMotion, false)
        .withoutSystemWritingTools()
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .topLeading)
        .background { windowBackground }
    }

    private var windowBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            // A faint wash gives the glass tiles something to pick up.
            LinearGradient(
                colors: [Liquid.accent.opacity(0.12), Color.clear, Liquid.iridescence[4].opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            WindowDragArea()
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Leaves room for the window's close button.
            Color.clear.frame(height: 34)
            ForEach(SettingsPage.allCases) { item in
                navigationRow(item)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 186)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { WindowDragArea() }
        .liquidGlass(in: PanelShape.tile)
    }

    private func navigationRow(_ item: SettingsPage) -> some View {
        let isSelected = item == page
        return Button {
            page = item
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(item.title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Liquid.accent : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(LiquidPressStyle())
    }

    private var content: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SettingsMetrics.gap) {
                switch page {
                case .general: GeneralSettingsView(model: model)
                case .writing: WritingSettingsView(model: model)
                case .styles: StylesSettingsView(model: model)
                case .shortcuts: ShortcutsSettingsView(model: model)
                case .access: AccessSettingsView(model: model)
                case .spending: SpendingSettingsView(model: model)
                case .about: AboutSettingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { WindowDragArea() }
            .id(page)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
