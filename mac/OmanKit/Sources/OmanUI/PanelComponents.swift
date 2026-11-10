import AppKit
import OmanCore
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 360
    static let gap: CGFloat = 8
    /// Below `gap`, so tiles stay separate at rest and only flow together while they move.
    static let blend: CGFloat = 6
    static let gripThickness: CGFloat = 12
    /// Clear space outside the glass, so the window edge doesn't cut off its shadow.
    static let shadowRoom: CGFloat = 10
    /// Room beside the tiles for the corner grip: one tile gap, the grip and its shadow.
    static let sideMargin = gap + gripThickness + shadowRoom
    static let bottomMargin: CGFloat = 24
    static let maxHeight: CGFloat = 640
    static let tileRadius: CGFloat = 22
}

enum PanelShape {
    static let tile = RoundedRectangle(cornerRadius: PanelMetrics.tileRadius, style: .continuous)
}

/// Morph identities shared between screens, so one tile flows into the next.
enum LiquidID {
    static let header = "header"
    static let body = "body"
    static let input = "input"
    static let actions = "actions"
}

struct PanelScrollArea<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.vertical) {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .scrollClipDisabled()
        }
    }
}

struct GlassTile<Content: View>: View {
    var id: String?
    var padding: CGFloat = 13
    @ViewBuilder var content: Content
    @Environment(\.panelIsFloating) private var isFloating

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if isFloating { WindowDragArea() } }
            .liquidGlass(in: PanelShape.tile, id: id)
    }
}

struct ActionCard: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentShape(PanelShape.tile)
            .liquidGlass(in: PanelShape.tile)
        }
        .buttonStyle(LiquidPressStyle())
    }
}

struct PanelIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.liquidMotion) private var hasMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(isHovering ? 0.12 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(LiquidPressStyle())
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering in
            withAnimation(hasMotion ? .easeOut(duration: 0.14) : nil) { isHovering = hovering }
        }
    }
}

struct PanelHeaderButtons: View {
    let model: PanelViewModel

    var body: some View {
        HStack(spacing: 0) {
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

struct SourceAppIcon: View {
    let bundleID: String?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
        }
    }

    private var image: NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct PanelInputField: View {
    let symbol: String
    let prompt: String
    @Binding var text: String
    var id: String? = LiquidID.input
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFocused ? AnyShapeStyle(Liquid.accent) : AnyShapeStyle(.secondary))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .focusEffectDisabled()
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 15)
        .frame(height: 42)
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
        .liquidGlass(in: Capsule(), id: id)
        .animation(.easeOut(duration: 0.16), value: isFocused)
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
                chip(title: "Create a style", symbol: "plus", isSelected: false, action: onCreate)
            } else {
                ForEach(styles) { style in
                    chip(title: style.displayName, symbol: nil, isSelected: style.id == selectedID) {
                        onSelect(style)
                    }
                }
            }
        }
        .animation(Liquid.press, value: selectedID)
    }

    private func chip(title: String, symbol: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 32)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Capsule())
            .liquidGlass(in: Capsule(), tint: isSelected ? Liquid.accent : nil)
        }
        .buttonStyle(LiquidPressStyle())
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
