import Foundation
import OmanCore

/// What the Lab shows: what was dictated, fixed and spent, and how the person's writing goes, all from what OmanAI
/// kept on this Mac.
struct LabSummary: Equatable {
    struct Day: Identifiable, Equatable {
        let start: Date
        let dictations: Int
        let fixes: Int
        var id: Date { start }
    }

    struct Week: Identifiable, Equatable {
        let start: Date
        /// How many places a proofread changed that week, on average. Nil for a week with no proofread.
        let changesPerProofread: Double?
        let proofreads: Int
        var id: Date { start }
    }

    /// The days of the activity chart, and the weeks of the writing chart.
    static let dayCount = 14
    static let weekCount = 8

    var dictations = 0
    var dictationsThisWeek = 0
    var wordsDictated = 0
    var secondsDictated: TimeInterval = 0
    var fixes = 0
    var fixesThisWeek = 0
    var written = 0
    var spentThisMonth: Double = 0
    var spentInAll: Double = 0
    /// Proofreads whose changes were counted, and those of them that changed nothing.
    var proofreads = 0
    var cleanProofreads = 0
    var changesThisWeek: Double?
    var changesLastWeek: Double?
    /// Oldest first.
    var days: [Day] = []
    var weeks: [Week] = []

    /// The share of proofreads that found nothing to change.
    var cleanShare: Double? { proofreads == 0 ? nil : Double(cleanProofreads) / Double(proofreads) }

    static func make(
        dictations: [SavedDictation],
        actions: [WritingAction],
        usage: [UsageEntry],
        now: Date,
        calendar: Calendar
    ) -> LabSummary {
        var summary = LabSummary()
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let lastWeek = thisWeek
            .flatMap { calendar.date(byAdding: .weekOfYear, value: -1, to: $0.start) }
            .flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        let month = calendar.dateInterval(of: .month, for: now)

        summary.dictations = dictations.count
        summary.dictationsThisWeek = dictations.filter { within(thisWeek, $0.date) }.count
        summary.wordsDictated = dictations.reduce(0) { $0 + words(in: $1.text) }
        summary.secondsDictated = dictations.reduce(0) { $0 + $1.duration }
        summary.fixes = actions.filter(\.applied).count
        summary.fixesThisWeek = actions.filter { $0.applied && within(thisWeek, $0.date) }.count
        summary.written = actions.count
        summary.spentThisMonth = usage.filter { within(month, $0.date) }.reduce(0) { $0 + $1.cost }
        summary.spentInAll = usage.reduce(0) { $0 + $1.cost }

        let proofreads = actions.filter { $0.kind == .proofread && $0.changes != nil }
        summary.proofreads = proofreads.count
        summary.cleanProofreads = proofreads.filter { $0.changes == 0 }.count
        summary.changesThisWeek = average(proofreads.filter { within(thisWeek, $0.date) })
        summary.changesLastWeek = average(proofreads.filter { within(lastWeek, $0.date) })

        let today = calendar.startOfDay(for: now)
        summary.days = (0..<dayCount).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .day, value: -back, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { return nil }
            let day = DateInterval(start: start, end: end)
            return Day(
                start: start,
                dictations: dictations.filter { within(day, $0.date) }.count,
                fixes: actions.filter { $0.applied && within(day, $0.date) }.count
            )
        }
        if let thisWeek {
            summary.weeks = (0..<weekCount).reversed().compactMap { back in
                guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek.start),
                      let week = calendar.dateInterval(of: .weekOfYear, for: start)
                else { return nil }
                let inWeek = proofreads.filter { within(week, $0.date) }
                return Week(start: week.start, changesPerProofread: average(inWeek), proofreads: inWeek.count)
            }
        }
        return summary
    }

    /// From the start of the interval up to, but not at, its end.
    private static func within(_ interval: DateInterval?, _ date: Date) -> Bool {
        guard let interval else { return false }
        return interval.start <= date && date < interval.end
    }

    private static func average(_ proofreads: [WritingAction]) -> Double? {
        let changes = proofreads.compactMap(\.changes)
        guard !changes.isEmpty else { return nil }
        return Double(changes.reduce(0, +)) / Double(changes.count)
    }

    static func words(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

enum LabFormat {
    /// "41 min" or "2 h 5 min"; under a minute, "under a minute".
    static func spoken(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else { return seconds > 0 ? "under a minute" : "0 min" }
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Changes per proofread, to one decimal.
    static func changes(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// How this week compares with the last, where fewer changes are better.
    static func trend(thisWeek: Double?, lastWeek: Double?) -> String? {
        guard let thisWeek, let lastWeek else { return nil }
        let difference = thisWeek - lastWeek
        if abs(difference) < 0.05 { return "The same as last week" }
        let amount = changes(abs(difference))
        return difference < 0 ? "\(amount) fewer than last week" : "\(amount) more than last week"
    }
}
