import Foundation
import OmanCore

/// What OmanAI did and what Claude cost, for the Spending page: one summary for each period that can be chosen
/// there.
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

    /// How many texts of one kind were written, and how many of them were put back.
    struct KindCount: Identifiable, Equatable {
        let kind: WritingTask.Kind
        var written = 0
        var fixes = 0
        /// What Claude cost for them.
        var cost: Double = 0
        var id: WritingTask.Kind { kind }
    }

    struct Bar: Identifiable, Equatable {
        let start: Date
        /// Where the hour, day or month ends, which is where the next bar starts.
        let end: Date
        let cost: Double
        /// Claude requests, which are what cost money.
        var requests = 0
        var tokens = 0
        /// Texts written, with any model.
        var written = 0
        /// Texts put back into an app with Replace or Insert.
        var fixes = 0
        /// Kinds with something written, in the order of `WritingTask.Kind.allCases`.
        var kinds: [KindCount] = []
        /// What each Claude model cost, most first.
        var models: [ModelShare] = []
        var id: Date { start }

        /// Where a label under the bar is centred.
        var middle: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }

        var isEmpty: Bool { written == 0 && requests == 0 }
    }

    struct ModelShare: Identifiable, Equatable {
        let name: String
        let cost: Double
        let requests: Int
        var id: String { name }
    }

    /// The apps texts were written for, by how many were put back there.
    struct AppShare: Identifiable, Equatable {
        let name: String
        let written: Int
        let fixes: Int
        var id: String { name }
    }

    struct PeriodSummary: Equatable {
        /// One bar for every hour, day or month of the period, oldest first, including those with nothing in them.
        let bars: [Bar]
        let cost: Double
        let requests: Int
        /// Every token sent and received, cached or not.
        let tokens: Int
        /// Every model that was ever used, most expensive over all time first, so the list keeps its length and
        /// order from one period to the next.
        let models: [ModelShare]
        var written = 0
        var fixes = 0
        /// Every kind with something written or spent.
        var kinds: [KindCount] = []
        /// What Claude cost for requests from before OmanAI noted their kind.
        var unsplitCost: Double = 0
        /// Apps with something written for them, most fixes first.
        var apps: [AppShare] = []

        var averageCost: Double { requests == 0 ? 0 : cost / Double(requests) }
    }

    /// All time shows at least this many months, so a first month of use isn't one bar as wide as the chart.
    static let minimumMonths = 6

    private let periods: [Period: PeriodSummary]
    let hasEntries: Bool

    subscript(period: Period) -> PeriodSummary {
        periods[period] ?? PeriodSummary(bars: [], cost: 0, requests: 0, tokens: 0, models: [])
    }

    static func make(
        from entries: [UsageEntry],
        actions: [WritingAction] = [],
        now: Date,
        calendar: Calendar
    ) -> SpendingSummary {
        let modelOrder = shares(of: entries, order: nil).map(\.name)
        var periods: [Period: PeriodSummary] = [:]
        for period in Period.allCases {
            let interval = interval(of: period, dates: entries.map(\.date) + actions.map(\.date), now: now, calendar: calendar)
            let inPeriod = entries.filter { interval.start <= $0.date && $0.date < interval.end }
            let actionsInPeriod = actions.filter { interval.start <= $0.date && $0.date < interval.end }
            var entriesByBar: [Date: [UsageEntry]] = [:]
            for entry in inPeriod {
                if let start = calendar.dateInterval(of: period.barUnit, for: entry.date)?.start {
                    entriesByBar[start, default: []].append(entry)
                }
            }
            var actionsByBar: [Date: [WritingAction]] = [:]
            for action in actionsInPeriod {
                if let start = calendar.dateInterval(of: period.barUnit, for: action.date)?.start {
                    actionsByBar[start, default: []].append(action)
                }
            }
            var summary = PeriodSummary(
                bars: spans(of: period.barUnit, in: interval, calendar: calendar).map {
                    bar($0, entries: entriesByBar[$0.start] ?? [], actions: actionsByBar[$0.start] ?? [])
                },
                cost: inPeriod.reduce(0) { $0 + $1.cost },
                requests: inPeriod.count,
                tokens: inPeriod.reduce(0) { $0 + $1.tokens.promptTokens + $1.tokens.output },
                models: shares(of: inPeriod, order: modelOrder)
            )
            summary.written = actionsInPeriod.count
            summary.fixes = actionsInPeriod.filter(\.applied).count
            summary.kinds = kinds(of: actionsInPeriod, entries: inPeriod).filter { $0.written > 0 || $0.cost > 0 }
            summary.unsplitCost = inPeriod.filter { $0.kind == nil }.reduce(0) { $0 + $1.cost }
            summary.apps = apps(of: actionsInPeriod)
            periods[period] = summary
        }
        return SpendingSummary(periods: periods, hasEntries: !entries.isEmpty || !actions.isEmpty)
    }

    private static func bar(_ span: DateInterval, entries: [UsageEntry], actions: [WritingAction]) -> Bar {
        Bar(
            start: span.start,
            end: span.end,
            cost: entries.reduce(0) { $0 + $1.cost },
            requests: entries.count,
            tokens: entries.reduce(0) { $0 + $1.tokens.promptTokens + $1.tokens.output },
            written: actions.count,
            fixes: actions.filter(\.applied).count,
            kinds: kinds(of: actions, entries: []).filter { $0.written > 0 },
            models: shares(of: entries, order: nil)
        )
    }

    private static func kinds(of actions: [WritingAction], entries: [UsageEntry]) -> [KindCount] {
        WritingTask.Kind.allCases.map { kind in
            let ofKind = actions.filter { $0.kind == kind }
            return KindCount(
                kind: kind,
                written: ofKind.count,
                fixes: ofKind.filter(\.applied).count,
                cost: entries.filter { $0.kind == kind }.reduce(0) { $0 + $1.cost }
            )
        }
    }

    private static func apps(of actions: [WritingAction]) -> [AppShare] {
        var written: [String: Int] = [:]
        var fixes: [String: Int] = [:]
        for action in actions {
            guard let name = action.appName, !name.isEmpty else { continue }
            written[name, default: 0] += 1
            if action.applied { fixes[name, default: 0] += 1 }
        }
        return written.keys
            .map { AppShare(name: $0, written: written[$0] ?? 0, fixes: fixes[$0] ?? 0) }
            .sorted { ($0.fixes, $0.written, $1.name) > ($1.fixes, $1.written, $0.name) }
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

    /// The top of the fixes scale: an even number, so the middle of the axis is a whole number too.
    static func countScale(for largest: Int) -> Int {
        var magnitude = 1
        while true {
            for step in [2, 4, 6, 8, 10] where step * magnitude >= largest {
                return step * magnitude
            }
            magnitude *= 10
        }
    }

    /// The top of the money scale: a round amount, so its middle is one too. At least one cent.
    static func costScale(for largest: Double) -> Double {
        var magnitude = 0.01
        while true {
            for step in [1.0, 2, 3, 4, 5] where step * magnitude >= largest - 1e-12 {
                return step * magnitude
            }
            magnitude *= 10
        }
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

    private static func interval(of period: Period, dates: [Date], now: Date, calendar: Calendar) -> DateInterval {
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
            let first = dates.min().flatMap { calendar.dateInterval(of: .month, for: $0)?.start } ?? padded
            // A clock that was set wrong can leave an entry dated after now. It still counts.
            let last = dates.max().flatMap { calendar.dateInterval(of: .month, for: $0)?.end } ?? month.end
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

    /// An amount on its own, such as in the details of one bar, to a tenth of a cent where that matters.
    static func precise(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: "USD").precision(.fractionLength(dollars > 0 && dollars < 0.01 ? 4 : 2)))
    }

    static func fixes(_ count: Int) -> String {
        count == 1 ? "1 fix put back" : "\(count.formatted()) fixes put back"
    }

    static func written(_ count: Int) -> String {
        "\(count.formatted()) written"
    }

    /// What one bar covers, as the details of a bar title it.
    static func title(of bar: SpendingSummary.Bar, in period: SpendingSummary.Period) -> String {
        switch period {
        case .today:
            let hours = Date.FormatStyle.dateTime.hour().minute()
            return "\(bar.start.formatted(hours)) to \(bar.end.formatted(hours))"
        case .thisWeek, .thisMonth, .lastMonth:
            return bar.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .allTime:
            return bar.start.formatted(.dateTime.month(.wide).year())
        }
    }

    /// The kinds written in a bar, as "Proofread 5 · Rewrite 2".
    static func kinds(_ kinds: [SpendingSummary.KindCount]) -> String {
        kinds.map { "\($0.kind.displayName) \($0.written)" }.joined(separator: " · ")
    }

    /// What each model cost in a bar, as "Claude Haiku $0.0015 · Claude Sonnet $0.0006".
    static func models(_ models: [SpendingSummary.ModelShare]) -> String {
        models.map { "\($0.name) \(precise($0.cost))" }.joined(separator: " · ")
    }

    /// Thousands and millions in short, as in 412K.
    static func tokens(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName)) + (count == 1 ? " token" : " tokens")
    }
}
