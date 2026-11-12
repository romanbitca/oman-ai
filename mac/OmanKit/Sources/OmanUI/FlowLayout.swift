import SwiftUI

/// Lays its children out in rows, as words wrap in text, starting a new row when the next child would not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    /// Between rows; `spacing` when nil.
    var lineSpacing: CGFloat?
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            if alignment == .center {
                x += max((bounds.width - row.width) / 2, 0)
            } else if alignment == .trailing {
                x += max(bounds.width - row.width, 0)
            }
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                // Each child sits on the row's baseline, so words of one line line up.
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y + row.height - size.height),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        let gap = lineSpacing ?? spacing
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                let next = Row(indices: [], y: row.y + row.height + gap)
                rows.append(next)
                row = next
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
