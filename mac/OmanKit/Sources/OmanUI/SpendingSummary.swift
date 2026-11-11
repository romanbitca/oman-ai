import Foundation
import OmanCore

/// What Claude cost, for the Spending page: one summary for each period that can be chosen there.
struct SpendingSummary: Equatable {
    enum Period: String, CaseIterable, Identifiable {
        case today, thisWeek, thisMonth, lastMonth, allTime

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .thisWeek: "This week"
            case .thisMonth: "This month"
            case .lastMonth: "Last month"
            case .allTime: "All time"
            }
        }

        /// What one bar of the period's chart covers.
        var barUnit: Calendar.Component {
            switch self {
            case .today: .hour
            case .thisWeek, .thisMonth, .lastMonth: .day
            case .allTime: .month
            }
        }
    }

    struct Bar: Identifiable, Equatable {
        let start: Date
        /// Where the hour, day or month ends, which is where the next bar starts.
        let end: Date
        let cost: Double
        var id: Date { start }

        /// Where a label under the bar is centred.
        var middle: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    }

    struct ModelShare: Identifiable, Equatable {
        let name: String
        let cost: Double
        let requests: Int
        var id: String { name }
    }

    struct PeriodSummary: Equatable {
        /// One bar for every hour, day or month of the period, oldest first, including those with nothing spent.
        let bars: [Bar]
        let cost: Double
        let requests: Int
        /// Every token sent and received, cached or not.
        let tokens: Int
        /// Every model that was ever used, most expensive over all time first, so the list keeps its length and
        /// order from one period to the next.
        let models: [ModelShare]

        var averageCost: Double { requests == 0 ? 0 : cost / Double(requests) }
    }

    /// All time shows at least this many months, so a first month of use isn't one bar as wide as the chart.
    static let minimumMonths = 6

    private let periods: [Period: PeriodSummary]
    let hasEntries: Bool

    subscript(period: Period) -> PeriodSummary {
        periods[period] ?? PeriodSummary(bars: [], cost: 0, requests: 0, tokens: 0, models: [])
    }

    static func make(from entries: [UsageEntry], now: Date, calendar: Calendar) -> SpendingSummary {
        let modelOrder = shares(of: entries, order: nil).map(\.name)
        var periods: [Period: PeriodSummary] = [:]
        for period in Period.allCases {
            let interval = interval(of: period, entries: entries, now: now, calendar: calendar)
            let inPeriod = entries.filter { interval.start <= $0.date && $0.date < interval.end }
            var byBar: [Date: Double] = [:]
            for entry in inPeriod {
                if let start = calendar.dateInterval(of: period.barUnit, for: entry.date)?.start {
                    byBar[start, default: 0] += entry.cost
                }
            }
            periods[period] = PeriodSummary(
                bars: spans(of: period.barUnit, in: interval, calendar: calendar).map {
                    Bar(start: $0.start, end: $0.end, cost: byBar[$0.start] ?? 0)
                },
                cost: inPeriod.reduce(0) { $0 + $1.cost },
                requests: inPeriod.count,
                tokens: inPeriod.reduce(0) { $0 + $1.tokens.promptTokens + $1.tokens.output },
                models: shares(of: inPeriod, order: modelOrder)
            )
        }
        return SpendingSummary(periods: periods, hasEntries: !entries.isEmpty)
    }

    /// The bars that get a date under them: as many as fit side by side.
    static func labelledBars(_ bars: [Bar], for period: Period) -> [Bar] {
        let step: Int
        // Counted from the first bar where that is a round start, such as midnight or the 1st, and back from
        // the newest month otherwise.
        var fromEnd = false
        switch period {
        case .today: step = 6
        case .thisWeek: step = 1
        case .thisMonth, .lastMonth: step = 7
        case .allTime:
            step = max(1, Int((Double(bars.count) / 8).rounded(.up)))
            fromEnd = true
        }
        return bars.enumerated()
            .filter { (fromEnd ? bars.count - 1 - $0.offset : $0.offset) % step == 0 }
            .map(\.element)
    }

    /// The name people know a model by. Anthropic's own name for it may end in a date.
    static func displayName(forModel served: String) -> String {
        WritingModel.allCases.first { !$0.isLocal && served.hasPrefix($0.rawValue) }?.displayName ?? served
    }

    /// With an `order`, every name in it gets a share, in that order, even when nothing was spent on it.
    private static func shares(of entries: [UsageEntry], order: [String]?) -> [ModelShare] {
        var cost: [String: Double] = [:]
        var requests: [String: Int] = [:]
        for entry in entries {
            let name = displayName(forModel: entry.model)
            cost[name, default: 0] += entry.cost
            requests[name, default: 0] += 1
        }
        let names = order ?? cost.keys.sorted { (cost[$0] ?? 0, $1) > (cost[$1] ?? 0, $0) }
        return names.map { ModelShare(name: $0, cost: cost[$0] ?? 0, requests: requests[$0] ?? 0) }
    }

    private static func interval(of period: Period, entries: [UsageEntry], now: Date, calendar: Calendar) -> DateInterval {
        let day = DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)
        let month = calendar.dateInterval(of: .month, for: now) ?? day
        switch period {
        case .today:
            return calendar.dateInterval(of: .day, for: now) ?? day
        case .thisWeek:
            // Weeks start on the day the person's region starts them.
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? day
        case .thisMonth:
            return month
        case .lastMonth:
            let before = calendar.date(byAdding: .day, value: -1, to: month.start) ?? month.start
            return calendar.dateInterval(of: .month, for: before) ?? month
        case .allTime:
            let padded = calendar.date(byAdding: .month, value: 1 - minimumMonths, to: month.start) ?? month.start
            let first = entries.map(\.date).min().flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? padded
            // A clock that was set wrong can leave an entry dated after now. It still counts.
            let last = entries.map(\.date).max().flatMap { calendar.dateInterval(of: .month, for: $0)?.end } ?? month.end
            return DateInterval(start: min(first, padded), end: max(last, month.end))
        }
    }

    /// Every hour, day or month of `interval`, in order.
    private static func spans(of unit: Calendar.Component, in interval: DateInterval, calendar: Calendar) -> [DateInterval] {
        var spans: [DateInterval] = []
        var start = interval.start
        while start < interval.end {
            guard let end = calendar.date(byAdding: unit, value: 1, to: start), end > start else { break }
            spans.append(DateInterval(start: start, end: end))
            start = end
        }
        return spans
    }
}

enum SpendingFormat {
    /// Two decimals, or "< $0.01" for a small amount that would otherwise read as nothing.
    static func amount(_ dollars: Double) -> String {
        let cents = FloatingPointFormatStyle<Double>.Currency(code: "USD").precision(.fractionLength(2))
        if dollars > 0, dollars < 0.01 {
            return "< " + 0.01.formatted(cents)
        }
        return dollars.formatted(cents)
    }

    /// Chart axes show small steps such as $0.005, so they keep up to three decimals.
    static func axis(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: "USD").precision(.fractionLength(0...3)))
    }

    /// One request often costs a fraction of a cent, so an average keeps up to four decimals.
    static func average(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: "USD").precision(.fractionLength(2...4)))
    }

    static func requests(_ count: Int) -> String {
        count == 1 ? "1 request" : "\(count.formatted()) requests"
    }

    /// Thousands and millions in short, as in 412K.
    static func tokens(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName)) + (count == 1 ? " token" : " tokens")
    }
}
