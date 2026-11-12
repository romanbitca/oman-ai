import OmanCore
import SwiftUI

/// The year at a glance, as GitHub draws contributions: a square for every day, darker for more, a week in each
/// column. Pointing at a square says what the day held.
struct HomeMapCard: View {
    let summary: HomeSummary
    @Binding var metric: HomeSummary.MapMetric
    let calendar: Calendar
    @State private var hovered: Hovered?

    struct Hovered: Equatable {
        let week: Int
        let day: Int
    }

    /// `pointingAt` starts with the pointer on a square, for drawing the card with its note showing.
    init(summary: HomeSummary, metric: Binding<HomeSummary.MapMetric>, calendar: Calendar, pointingAt: Hovered? = nil) {
        self.summary = summary
        _metric = metric
        self.calendar = calendar
        _hovered = State(initialValue: pointingAt)
    }

    /// A square's gap, as a share of the square and its gap together.
    private static let gapShare: CGFloat = 0.19
    private static let labelsWidth: CGFloat = 30

    private var weeks: Int { max(summary.map.count, 1) }

    /// The grid is as wide as the card lets it be, and as tall as that makes seven rows.
    private var aspect: CGFloat { (CGFloat(weeks) - Self.gapShare) / (7 - Self.gapShare) }

    private func shades(_ metric: HomeSummary.MapMetric) -> [Color] {
        switch metric {
        case .words: [HomePalette.off, HomePalette.map1, HomePalette.map2, HomePalette.map3, HomePalette.map4]
        case .fixes: [HomePalette.off, HomePalette.fix1, HomePalette.fix2, HomePalette.fix3, HomePalette.fix4]
        }
    }

    private var title: String {
        let total = summary.mapTotal(metric)
        switch metric {
        case .words: return "\(total == 1 ? "1 word" : "\(total.formatted()) words") in the last 12 months"
        case .fixes: return "\(total == 1 ? "1 fix" : "\(total.formatted()) fixes") in the last 12 months"
        }
    }

    private func isCounted(_ day: HomeSummary.MapDay) -> Bool {
        guard let since = summary.countedSince else { return false }
        return day.date >= since
    }

    /// The first letters of months, each over the first week that begins in it.
    private var months: [(week: Int, name: String)] {
        var result: [(Int, String)] = []
        var last: Int?
        var style = Date.FormatStyle.dateTime.month(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        for (index, week) in summary.map.enumerated() {
            guard let first = week.first else { continue }
            let month = calendar.component(.month, from: first.date)
            if month != last, calendar.component(.day, from: first.date) <= 7 {
                result.append((index, first.date.formatted(style)))
            }
            last = month
        }
        return result
    }

    /// Mon, Wed and Fri where the week begins on Monday: the first, third and fifth rows.
    private var weekdays: [(row: Int, name: String)] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return [] }
        return [0, 2, 4].map { ($0, symbols[(calendar.firstWeekday - 1 + $0) % 7]) }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 14.5, weight: .semibold)).contentTransition(.numericText())
                Spacer(minLength: 8)
                HomeChips(values: HomeSummary.MapMetric.allCases, selection: $metric, isSmall: true) { $0.title }
            }
            grid.padding(.top, 10)
            HStack(spacing: 3) {
                if let since = summary.countedSince {
                    Text("Counted since \(since.formatted(sinceStyle))")
                }
                Spacer(minLength: 8)
                Text("Less")
                ForEach(Array(shades(metric).enumerated()), id: \.offset) { _, shade in
                    RoundedRectangle(cornerRadius: 2.8, style: .continuous).fill(shade).frame(width: 10, height: 10)
                }
                Text("More")
            }
            .font(.system(size: 11))
            .foregroundStyle(HomePalette.soft)
            .padding(.leading, Self.labelsWidth)
            .padding(.top, 9)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomePalette.card)
        .clipShape(shape)
        .overlay { shape.strokeBorder(HomePalette.edge, lineWidth: 1) }
        .shadow(color: HomePalette.shadow, radius: 12, x: 0, y: 8)
    }

    private var sinceStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: 0) {
            // The names of three days, beside their rows.
            GeometryReader { proxy in
                let step = (proxy.size.height - 16) / (7 - Self.gapShare)
                ForEach(weekdays, id: \.row) { weekday in
                    Text(weekday.name)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(HomePalette.soft)
                        .fixedSize()
                        .position(x: 12, y: 16 + step * (CGFloat(weekday.row) + 0.5 - Self.gapShare / 2))
                }
            }
            .frame(width: Self.labelsWidth)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { proxy in
                    let step = proxy.size.width / (CGFloat(weeks) - Self.gapShare)
                    ForEach(months, id: \.week) { month in
                        Text(month.name)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(HomePalette.soft)
                            .fixedSize()
                            .frame(width: 1, alignment: .leading)
                            .offset(x: step * CGFloat(month.week))
                    }
                }
                .frame(height: 12)
                .accessibilityHidden(true)

                squares
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay(alignment: .topLeading) { tip }
            }
        }
    }

    private var squares: some View {
        let peak = summary.mapPeak(metric)
        let shades = shades(metric)
        let today = summary.map.last?.last?.date
        return Canvas { context, size in
            let step = size.width / (CGFloat(weeks) - Self.gapShare)
            let side = step * (1 - Self.gapShare)
            let radius = side * 0.27
            for (weekIndex, week) in summary.map.enumerated() {
                for (dayIndex, day) in week.enumerated() {
                    let rect = CGRect(x: step * CGFloat(weekIndex), y: step * CGFloat(dayIndex), width: side, height: side)
                    let square = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
                    if isCounted(day) {
                        let level = HomeSummary.mapLevel(HomeSummary.value(of: day, metric), peak: peak)
                        context.fill(square, with: .color(shades[min(level, shades.count - 1)]))
                    } else {
                        // Nothing is known of days before counting began, so they are only outlined.
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius, style: .continuous), with: .color(HomePalette.off), lineWidth: 1)
                    }
                    if day.date == today {
                        // Drawn inside the square, so the last column's ring isn't cut at the edge.
                        context.stroke(Path(roundedRect: rect.insetBy(dx: 0.7, dy: 0.7), cornerRadius: radius, style: .continuous), with: .color(HomePalette.ink), lineWidth: 1.4)
                    }
                }
            }
        }
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(point):
                            let step = proxy.size.width / (CGFloat(weeks) - Self.gapShare)
                            let week = Int(point.x / step)
                            let day = Int(point.y / step)
                            if summary.map.indices.contains(week), summary.map[week].indices.contains(day) {
                                hovered = Hovered(week: week, day: day)
                            } else {
                                hovered = nil
                            }
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(title)
    }

    /// What the square under the pointer held, beside it.
    @ViewBuilder
    private var tip: some View {
        if let hovered, summary.map.indices.contains(hovered.week), summary.map[hovered.week].indices.contains(hovered.day) {
            let day = summary.map[hovered.week][hovered.day]
            GeometryReader { proxy in
                let step = proxy.size.width / (CGFloat(weeks) - Self.gapShare)
                let x = step * (CGFloat(hovered.week) + 0.5)
                let y = step * (CGFloat(hovered.day) + 0.5)
                // To the left of the square in the right half of the year, and to its right in the left half.
                let leftward = x > proxy.size.width / 2
                Text(HomeFormat.mapDay(day, metric: metric, counted: isCounted(day), calendar: calendar))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(HomePalette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(HomePalette.card)
                            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                    }
                    .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(HomePalette.edge, lineWidth: 1) }
                    .fixedSize()
                    .alignmentGuide(.leading) { size in leftward ? size.width + step : -step }
                    .frame(width: 0, height: 0, alignment: .leading)
                    .offset(x: x, y: y)
            }
            .allowsHitTesting(false)
        }
    }
}
