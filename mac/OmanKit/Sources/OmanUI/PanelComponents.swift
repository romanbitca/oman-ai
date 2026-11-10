import OmanCore
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 360
    static let padding: CGFloat = 14
    static let maxHeight: CGFloat = 560
    static let contentMaxHeight: CGFloat = maxHeight - padding * 2
}

struct PanelScrollArea<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: PanelMetrics.contentMaxHeight)
    }
}

struct PanelCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

struct ActionCard: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PanelCardButtonStyle())
    }
}

struct PanelIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct PanelHeaderButtons: View {
    let model: PanelViewModel

    var body: some View {
        HStack(spacing: 2) {
            PanelIconButton(
                symbol: model.isPinned ? "pin.fill" : "pin",
                label: model.isPinned ? "Unpin panel" : "Pin panel"
            ) {
                model.togglePin()
            }
            PanelIconButton(symbol: "gearshape", label: "Settings") {
                model.openSettings()
            }
        }
    }
}

struct PanelInputField: View {
    let symbol: String
    let prompt: String
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

struct NoticeText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StyleChipsView: View {
    let styles: [WritingStyle]
    let selectedID: UUID?
    let onSelect: (WritingStyle) -> Void
    let onCreate: () -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            if styles.isEmpty {
                Button(action: onCreate) {
                    chipLabel(title: "Create a style", symbol: "plus", isSelected: false)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(styles) { style in
                    Button {
                        onSelect(style)
                    } label: {
                        chipLabel(title: style.displayName, symbol: nil, isSelected: style.id == selectedID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chipLabel(title: String, symbol: String?, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            }
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(isSelected ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
        .contentShape(Capsule())
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        return arrange(maxWidth: maxWidth, sizes: subviews.map { $0.sizeThatFits(.unspecified) }).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let layout = arrange(maxWidth: bounds.width, sizes: sizes)
        for (index, subview) in subviews.enumerated() {
            let origin = layout.origins[index]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(width: min(sizes[index].width, bounds.width), height: sizes[index].height)
            )
        }
    }

    private func arrange(maxWidth: CGFloat, sizes: [CGSize]) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for size in sizes {
            let width = min(size.width, maxWidth)
            if x > 0, x + width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + width)
            lineHeight = max(lineHeight, size.height)
            x += width + spacing
        }
        return (origins, CGSize(width: usedWidth, height: y + lineHeight))
    }
}
