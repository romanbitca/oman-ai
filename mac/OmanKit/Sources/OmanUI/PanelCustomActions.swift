import OmanCore
import SwiftUI

/// The person's own actions, on one line under Proofread, Rewrite and Explain. Each runs at once on the selection,
/// so they have a tile of their own rather than a place among the template and context chips, which only choose.
struct CustomActionsRow: View {
    let actions: [CustomAction]
    let onRun: (CustomAction) -> Void

    /// Where the row's right end fades out, as the templates' row does, so a chip cut off there reads as "more
    /// this way".
    private static var fade: CGFloat { 18 }

    var body: some View {
        GlassTile(padding: 10) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(actions) { action in
                        chip(for: action)
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
        }
        .environment(\.isInsideGlassTile, true)
    }

    /// A sparkle, the panel's mark for an instruction, or reading glasses for an answer that is only read.
    static func symbol(for output: CustomAction.Output) -> String {
        switch output {
        case .paste: "sparkle"
        case .read: "eyeglasses"
        }
    }

    private func chip(for action: CustomAction) -> some View {
        Button {
            onRun(action)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: Self.symbol(for: action.output))
                    .font(.system(size: 10, weight: .semibold))
                    .accessibilityHidden(true)
                Text(action.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 13)
            .frame(height: 32)
            .foregroundStyle(Color.primary)
            .contentShape(Capsule())
            .toggleSurface(isOn: false)
        }
        .buttonStyle(GlassPressStyle())
        .fixedSize()
        .help(action.instruction)
        .accessibilityHint(action.instruction)
    }
}
