#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import OmanCore
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 360
    static let gap: CGFloat = 12
    static let gripThickness: CGFloat = 12
    /// Clear space outside the glass, so the window edge doesn't cut off its shadow.
    static let shadowRoom: CGFloat = 10
    /// Room beside the tiles for the corner grip: one tile gap, the grip and its shadow.
    static let sideMargin = gap + gripThickness + shadowRoom
    static let bottomMargin: CGFloat = 24
    /// From the menu bar's lower edge to the first tile. Control Center's first module starts 12 points below
    /// the bar, measured on screen: 11 below the top of the area apps may use, which is where the window hangs.
    static let menuBarGap: CGFloat = 11
    static let maxHeight: CGFloat = 640
    static let tileRadius: CGFloat = 26
}

enum PanelShape {
    static let tile = RoundedRectangle(cornerRadius: PanelMetrics.tileRadius, style: .continuous)
}

/// Identities shared between screens, so a tile moves and resizes into its counterpart on the next screen.
enum LiquidID {
    static let header = "header"
    static let body = "body"
    static let input = "input"
    static let actions = "actions"
    static let controls = "controls"
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
    /// For a tile that holds text to read or type.
    var reading = false
    @ViewBuilder var content: Content
    @Environment(\.panelIsFloating) private var isFloating

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if isFloating { WindowDragArea() } }
            .liquidGlass(in: PanelShape.tile, id: id, reading: reading)
    }
}

struct ActionCard: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Capsule())
            .liquidGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(GlassPressStyle())
    }
}

struct PanelIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var isHovering = false

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
            withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
        }
    }
}

struct PanelHeaderButtons: View {
    let model: PanelViewModel

    var body: some View {
        // The iPhone's panel is the app itself, so there is nothing to pin.
        #if os(iOS)
        EmptyView()
        #else
        HStack(spacing: 0) {
            PanelIconButton(
                symbol: model.isPinned ? "pin.fill" : "pin",
                label: model.isPinned ? "Unpin panel" : "Pin panel"
            ) {
                model.togglePin()
            }
        }
        #endif
    }
}

struct SourceAppIcon: View {
    let bundleID: String?

    var body: some View {
        if let image {
            Image(platformImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .keepingOwnColors()
        }
    }

    private var image: PlatformImage? {
        guard let bundleID else { return nil }
        return Platform.appIcon(bundleID: bundleID)
    }
}

struct PanelInputField: View {
    let symbol: String
    let prompt: String
    @Binding var text: String
    var id: String? = LiquidID.input
    /// With both set, a microphone at the end of the field dictates into it.
    var dictation: DictationController?
    var field: PanelField?
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
            if let dictation, let field {
                DictationMicButton(controller: dictation, field: field, isInField: true)
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, dictation != nil && field != nil ? 7 : 15)
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
    /// Called with nil for As written.
    let onSelect: (WritingStyle?) -> Void
    let onCreate: () -> Void

    /// Where the row's right end fades out, so a chip cut off there reads as "more this way".
    private static var fade: CGFloat { 18 }

    var body: some View {
        HStack(spacing: 8) {
            // One is always chosen. As written is no template: the person's own voice. It stays put while the
            // templates scroll, so it is always there to go back to.
            chip(title: "As written", symbol: nil, isSelected: selectedID == nil) {
                onSelect(nil)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 1, height: 18)
            templates
        }
        .animation(Liquid.press, value: selectedID)
    }

    /// The templates stay on one line and scroll sideways when there are more than fit.
    private var templates: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(styles) { style in
                        chip(title: style.displayName, symbol: nil, isSelected: style.id == selectedID) {
                            onSelect(style)
                        }
                        .id(style.id)
                    }
                    if styles.isEmpty {
                        chip(title: "Create a style", symbol: "plus", isSelected: false, action: onCreate)
                    }
                }
                .padding(.trailing, Self.fade)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.fade)
                }
            }
            // The template chosen for this app may be off to the right when the panel opens.
            .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
            .onChange(of: selectedID) { _, id in proxy.scrollTo(id, anchor: .center) }
        }
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
            .foregroundStyle(isSelected ? Color.black : Color.primary)
            .contentShape(Capsule())
            .toggleSurface(isOn: isSelected)
        }
        .buttonStyle(GlassPressStyle())
        .fixedSize()
    }
}

private struct ToggleSurface: ViewModifier {
    let isOn: Bool
    @Environment(\.isInsideGlassTile) private var isInsideTile

    func body(content: Content) -> some View {
        if isOn {
            // Solid, because tinted glass turns gray over a dark background.
            content.background(Capsule().fill(Color.white))
        } else if isInsideTile {
            content.background(Capsule().fill(Color.primary.opacity(0.13)))
        } else {
            content.liquidGlass(in: Capsule(), interactive: true)
        }
    }
}

/// The style and context chips, together in one tile as a Control Center module holds its toggles,
/// so an app's text never shows between them.
struct PanelControlsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GlassTile(id: LiquidID.controls, padding: 10) {
            VStack(alignment: .leading, spacing: PanelMetrics.gap) { content }
        }
        .environment(\.isInsideGlassTile, true)
    }
}

private struct InnerSurface<S: Shape>: ViewModifier {
    let shape: S
    let reading: Bool
    @Environment(\.isInsideGlassTile) private var isInsideTile

    func body(content: Content) -> some View {
        if isInsideTile {
            // Text to read or type gets a darker, calmer patch of its clear tile.
            content.background(shape.fill(reading ? Color.black.opacity(0.4) : Color.primary.opacity(0.08)))
        } else {
            content.liquidGlass(in: shape, reading: reading)
        }
    }
}

extension View {
    /// Glass on its own, or a flat fill when it sits inside a glass tile.
    func panelSurface<S: Shape>(in shape: S, reading: Bool = false) -> some View {
        modifier(InnerSurface(shape: shape, reading: reading))
    }
}

extension View {
    /// Glass when off and solid white when on, as a toggle is in Control Center.
    func toggleSurface(isOn: Bool) -> some View {
        modifier(ToggleSurface(isOn: isOn))
    }
}
