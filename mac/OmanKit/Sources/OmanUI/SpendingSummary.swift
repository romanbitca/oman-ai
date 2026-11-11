import Foundation
import OmanCore

/// What Claude cost, grouped by day and by week for the Spending page. Bars run oldest first and end today.
struct SpendingSummary: Equatable {
    struct Bar: Identifiable, Equatable {
        let start: Date
        let cost: Double
        var id: Date { start }
    }

    static let dayCount = 14
    static let weekCount = 8

    let days: [Bar]
    let weeks: [Bar]
    let today: Double
    let thisWeek: Double
    let hasEntries: Bool

    /// The start of the oldest week shown, which is as far back as anything needs to be loaded.
    static func earliestDate(now: Date, calendar: Calendar) -> Date {
        weekStarts(now: now, calendar: calendar).first ?? calendar.startOfDay(for: now)
    }

    static func make(from entries: [UsageEntry], now: Date, calendar: Calendar) -> SpendingSummary {
        var byDay: [Date: Double] = [:]
        var byWeek: [Date: Double] = [:]
        for entry in entries {
            byDay[calendar.startOfDay(for: entry.date), default: 0] += entry.cost
            if let week = calendar.dateInterval(of: .weekOfYear, for: entry.date)?.start {
                byWeek[week, default: 0] += entry.cost
            }
        }
        let days = dayStarts(now: now, calendar: calendar).map { Bar(start: $0, cost: byDay[$0] ?? 0) }
        let weeks = weekStarts(now: now, calendar: calendar).map { Bar(start: $0, cost: byWeek[$0] ?? 0) }
        return SpendingSummary(
            days: days,
            weeks: weeks,
            today: days.last?.cost ?? 0,
            thisWeek: weeks.last?.cost ?? 0,
            hasEntries: !entries.isEmpty
        )
    }

    private static func dayStarts(now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<dayCount).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Weeks start on the day the person's region starts them.
    private static func weekStarts(now: Date, calendar: Calendar) -> [Date] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weekCount).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
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
}
