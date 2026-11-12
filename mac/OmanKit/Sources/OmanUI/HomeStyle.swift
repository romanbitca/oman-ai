import AppKit
import SwiftUI

/// The colours of OmanAI's own window, each in a light and a dark form, and the brand's two gradients.
enum HomePalette {
    static let page = dynamic(light: 0xF4F6FA, dark: 0x17181B)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x232428)
    static let ink = dynamic(light: 0x0E1116, dark: 0xF3F4F6)
    static let dim = dynamic(light: 0x56606E, dark: 0xA3ACB9)
    static let soft = dynamic(light: 0x7F8896, dark: 0x7D8693)
    /// A dot or a bar with nothing in it.
    static let off = dynamic(light: 0xE9ECF1, dark: 0x34363C)
    static let chipOn = dynamic(light: 0xFFFFFF, dark: 0x3A3C42)
    static let line = dynamic(light: 0x0E1116, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.08)
    static let edge = dynamic(light: 0x0E1116, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.07)
    static let chip = dynamic(light: 0x0E1116, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.07)
    static let track = dynamic(light: 0x0E1116, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.08)
    static let hover = dynamic(light: 0x17CF9B, dark: 0x17CF9B, lightAlpha: 0.10, darkAlpha: 0.16)
    static let shadow = dynamic(light: 0x10224A, dark: 0x000000, lightAlpha: 0.10, darkAlpha: 0.45)
    static let green = dynamic(light: 0x067A5F, dark: 0x3DDCAE)
    static let violet = dynamic(light: 0x5B4CF5, dark: 0xA59CFF)
    static let teal = dynamic(light: 0x0A9AA0, dark: 0x35C6CC)
    static let orange = Color(hex: 0xF76707)
    static let mint = Color(hex: 0x17CF9B)
    static let blue = Color(hex: 0x1F6FD0)
    static let copy = Color(hex: 0x0AA37F)

    /// The year map's four shades for words, mint into blue, and for fixes, in violet.
    static let map1 = dynamic(light: 0xB9F1E0, dark: 0x1D5C57)
    static let map2 = dynamic(light: 0x5CDCB8, dark: 0x178F7F)
    static let map3 = dynamic(light: 0x12B3A0, dark: 0x17CF9B)
    static let map4 = dynamic(light: 0x1F6FD0, dark: 0x6FB1FF)
    static let fix1 = dynamic(light: 0xDDD6FF, dark: 0x3A3470)
    static let fix2 = dynamic(light: 0xB3A5FB, dark: 0x5A4FC0)
    static let fix3 = dynamic(light: 0x8A72F6, dark: 0x8A7BF6)
    static let fix4 = dynamic(light: 0x5B4CF5, dark: 0xB9B0FF)

    static var pageNSColor: NSColor { nsDynamic(light: 0xF4F6FA, dark: 0x17181B) }

    /// The first tile: OmanAI's teal into blue, with violet rising from one corner and light falling on the other.
    static var heroFill: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x19D3A2), location: 0),
                    .init(color: Color(hex: 0x0C9EA3), location: 0.5),
                    .init(color: blue, location: 1),
                ],
                startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 0.9)
            )
            // Violet only rises from the far corner, so the tile stays OmanAI's teal for most of its width.
            RadialGradient(
                colors: [Color(hex: 0x5B4CF5), Color(hex: 0x5B4CF5).opacity(0)],
                center: .bottomTrailing, startRadius: 0, endRadius: 270
            )
            RadialGradient(colors: [.white.opacity(0.20), .white.opacity(0)], center: .topLeading, startRadius: 0, endRadius: 330)
        }
    }

    /// The one coloured tile of the second row: violet into pink.
    static var accentFill: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x7B5CF7), location: 0),
                    .init(color: Color(hex: 0xC14FD0), location: 0.55),
                    .init(color: Color(hex: 0xF0568B), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(colors: [.white.opacity(0.18), .white.opacity(0)], center: .topLeading, startRadius: 0, endRadius: 200)
        }
    }

    static let barFill = LinearGradient(colors: [mint, blue], startPoint: .leading, endPoint: .trailing)

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: nsDynamic(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha))
    }

    private static func nsDynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha
            )
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255
        )
    }
}

enum HomeMetrics {
    static let windowSize = CGSize(width: 780, height: 880)
    static let minWindowSize = CGSize(width: 700, height: 520)
    static let maxContentWidth: CGFloat = 900
    static let sideMargin: CGFloat = 24
    static let gap: CGFloat = 12
    static let tileRadius: CGFloat = 22
    static let heroHeight: CGFloat = 262
    static let smallHeight: CGFloat = 125
    static let wideHeight: CGFloat = 160
}

/// One row on a grid of equal columns with gaps: each subview takes the number of columns it is given, and all are
/// as tall as the tallest.
struct HomeColumns: Layout {
    var spans: [Int]
    var columns = 6
    var spacing = HomeMetrics.gap

    private func width(of index: Int, in total: CGFloat) -> CGFloat {
        let column = (total - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let span = CGFloat(index < spans.count ? spans[index] : 1)
        return column * span + spacing * (span - 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? HomeMetrics.windowSize.width
        let height = subviews.enumerated().map { index, subview in
            subview.sizeThatFits(ProposedViewSize(width: width(of: index, in: total), height: nil)).height
        }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let width = width(of: index, in: bounds.width)
            subview.place(
                at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}

/// A tile: a rounded card, white or in colour.
struct HomeTile<Fill: View, Content: View>: View {
    var height: CGFloat
    var glow: Color = HomePalette.shadow
    @ViewBuilder var fill: Fill
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous)
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .background { fill }
            .clipShape(shape)
            .overlay { shape.strokeBorder(HomePalette.edge, lineWidth: 1) }
            .shadow(color: glow, radius: 10, x: 0, y: 6)
    }
}

extension HomeTile where Fill == Color {
    init(height: CGFloat, @ViewBuilder content: () -> Content) {
        self.init(height: height, fill: { HomePalette.card }, content: content)
    }
}

/// What a tile is about: a small symbol and a word, in the tile's own colour.
struct HomeLabel: View {
    var symbol: String?
    let title: String
    var color = HomePalette.dim

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold))
            }
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(color)
    }
}

/// A large rounded figure with its unit beside it.
struct HomeFigure: View {
    let value: String
    var unit: String?
    var size: CGFloat = 32
    var unitColor = HomePalette.dim

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .tracking(-size / 32)
                .contentTransition(.numericText())
            if let unit {
                Text(unit).font(.system(size: max(14, size * 0.42), weight: .semibold)).foregroundStyle(unitColor)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}
