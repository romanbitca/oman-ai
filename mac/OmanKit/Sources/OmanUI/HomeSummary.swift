import Foundation
import OmanCore

/// What OmanAI's own window says about a stretch of time: what was dictated and fixed, how fast, how often, where,
/// and how the person's writing goes. All of it from counts kept on this Mac, never from the words.
struct HomeSummary: Equatable {
    enum Period: String, CaseIterable, Identifiable, Sendable {
        case week, month, all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: "This week"
            case .month: "This month"
            case .all: "All time"
            }
        }
    }

    enum StepLength: Equatable { case day, week, month }

    /// One step of the line in the first tile: a day of the week or month, or a week or month of all time.
    struct Step: Equatable, Identifiable {
        let start: Date
        var words = 0
        var fixes = 0
        var seconds: TimeInterval = 0
        var id: Date { start }

        /// Minutes typing the step's words would have taken beyond the time spent speaking them.
        var minutesSaved: Int {
            max(0, Int((Double(words) / HomeSummary.typingSpeed - seconds / 60).rounded()))
        }
    }

    struct Streak: Equatable {
        /// Days in a row on which something was dictated or written, up to today, or up to yesterday while
        /// today has nothing yet.
        var days = 0
        var longest = 0
        var includesToday = false
        /// The seven days of this week, its first day first: whether OmanAI was used.
        var week: [Bool] = []
        var todayIndex = 0
    }

    struct AppShare: Equatable, Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    /// Texts OmanAI wrote that were put back into an app.
    struct Fixes: Equatable {
        var proofread = 0
        var rewritten = 0
        var composed = 0
        var total: Int { proofread + rewritten + composed }
    }

    struct English: Equatable {
        /// How many places a proofread changed, on average, in this stretch.
        var average: Double
        /// The same for the stretch before. Nil for all time, and when nothing was proofread then.
        var previous: Double?
        var proofreads: Int
        /// Proofreads that found nothing to change.
        var clean: Int
        /// The last eight weeks, oldest first, for the small line. Nil for a week with no proofread.
        var weeks: [Double?]
    }

    /// One square of the year map.
    struct MapDay: Equatable, Identifiable {
        let date: Date
        var words = 0
        var fixes = 0
        var seconds: TimeInterval = 0
        var id: Date { date }

        /// Minutes typing the day's words would have taken beyond the time spent speaking them.
        var minutesSaved: Int {
            max(0, Int((Double(words) / HomeSummary.typingSpeed - seconds / 60).rounded()))
        }
    }

    enum MapMetric: String, CaseIterable, Identifiable, Sendable {
        case words, fixes

        var id: String { rawValue }
        var title: String { self == .words ? "Words" : "Fixes" }
    }

    enum Hero: Equatable { case words, fixes, welcome }
    enum SmallTile: Equatable { case streak, speed, dictateTip }
    enum WideTile: Equatable { case timeSaved, fixes, english, apps, englishInvite }

    /// What typing is taken to be, for "faster than typing" and "time saved": the usual figure for an adult.
    static let typingSpeed = 40.0
    static let wordsPerPage = 275.0
    static let weekCount = 8
    /// The year map shows this many weeks, the current one last, as GitHub's does.
    static let mapWeekCount = 53
    static let mapLevels = 4
    /// Beyond this many weeks, all time is cut into months.
    static let mostWeeks = 52

    var period = Period.week
    var dictations = 0
    var words = 0
    var seconds: TimeInterval = 0
    var steps: [Step] = []
    var stepLength = StepLength.day
    /// The step today falls in.
    var todayStep: Int?
    var streak = Streak()
    var apps: [AppShare] = []
    var fixes = Fixes()
    var english: English?
    /// The year map: a week in each column, its first day first. The current week stops at today.
    var map: [[MapDay]] = []
    /// The first day anything was counted. Squares before it are drawn empty: nothing is known of them.
    var countedSince: Date?

    /// Whether anything of the kind was ever counted, which decides the tiles, so they don't come and go with
    /// every quiet week.
    var everDictated = false
    var everFixed = false
    var everWrote = false
    var everMeasured = false

    /// Words a minute while dictating, pauses included.
    var speed: Int? {
        guard words > 0, seconds >= 1 else { return nil }
        return Int((Double(words) / seconds * 60).rounded())
    }

    /// How many times faster than typing. Nil when it isn't faster.
    var timesFasterThanTyping: Double? {
        guard let speed, Double(speed) > Self.typingSpeed else { return nil }
        return Double(speed) / Self.typingSpeed
    }

    /// Minutes typing the same words would have taken beyond the time spent speaking them.
    var minutesSaved: Int {
        max(0, Int((Double(words) / Self.typingSpeed - seconds / 60).rounded()))
    }

    var pages: Int { Int((Double(words) / Self.wordsPerPage).rounded()) }

    func mapTotal(_ metric: MapMetric) -> Int {
        map.joined().reduce(0) { $0 + Self.value(of: $1, metric) }
    }

    /// The most of any day on the map.
    func mapPeak(_ metric: MapMetric) -> Int {
        map.joined().map { Self.value(of: $0, metric) }.max() ?? 0
    }

    /// How dark a day's square is, from 0 for nothing to `mapLevels` for the busiest days of the year shown.
    func mapLevel(of day: MapDay, _ metric: MapMetric) -> Int {
        Self.mapLevel(Self.value(of: day, metric), peak: mapPeak(metric))
    }

    static func mapLevel(_ value: Int, peak: Int) -> Int {
        guard value > 0, peak > 0 else { return 0 }
        return min(mapLevels, 1 + Int(Double(value) / Double(peak) * (Double(mapLevels) - 0.001)))
    }

    static func value(of day: MapDay, _ metric: MapMetric) -> Int {
        metric == .words ? day.words : day.fixes
    }

    var hero: Hero {
        if everDictated { return .words }
        return everWrote ? .fixes : .welcome
    }

    var smallTiles: [SmallTile] { [.streak, everDictated ? .speed : .dictateTip] }

    /// The three tiles of the second row. The ones with most to say are chosen, then shown in one steady order.
    var wideTiles: [WideTile] {
        var chosen: [WideTile] = []
        if everFixed, hero != .fixes { chosen.append(.fixes) }
        if everMeasured { chosen.append(.english) }
        if !apps.isEmpty || everDictated { chosen.append(.apps) }
        if everDictated { chosen.append(.timeSaved) }
        if !everMeasured { chosen.append(.englishInvite) }
        let kept = Set(chosen.prefix(3).map(Self.order))
        return [WideTile.timeSaved, .fixes, .english, .apps, .englishInvite].filter { kept.contains(Self.order($0)) }
    }

    /// The one tile of the second row in colour.
    var accentTile: WideTile? {
        let tiles = wideTiles
        if tiles.contains(.english) { return .english }
        if tiles.contains(.timeSaved) { return .timeSaved }
        return nil
    }

    private static func order(_ tile: WideTile) -> Int {
        switch tile {
        case .timeSaved: 0
        case .fixes: 1
        case .english: 2
        case .apps: 3
        case .englishInvite: 4
        }
    }

    static func make(
        counts: [DictationCount],
        actions: [WritingAction],
        period: Period,
        now: Date,
        calendar: Calendar
    ) -> HomeSummary {
        var summary = HomeSummary()
        summary.period = period
        summary.everDictated = !counts.isEmpty
        summary.everWrote = !actions.isEmpty
        summary.everFixed = actions.contains(where: \.applied)

        let span = interval(of: period, now: now, calendar: calendar)
        let inSpan = counts.filter { within(span, $0.date) }
        let written = actions.filter { within(span, $0.date) }
        let fixed = written.filter(\.applied)

        summary.dictations = inSpan.count
        summary.words = inSpan.reduce(0) { $0 + $1.words }
        summary.seconds = inSpan.reduce(0) { $0 + $1.duration }
        summary.fixes = Fixes(
            proofread: fixed.filter { $0.kind == .proofread }.count,
            rewritten: fixed.filter { $0.kind == .rewrite }.count,
            composed: fixed.filter { $0.kind == .compose }.count
        )

        let measured = actions.filter { $0.kind == .proofread && $0.changes != nil }
        summary.everMeasured = !measured.isEmpty
        let measuredInSpan = measured.filter { within(span, $0.date) }
        if let average = average(measuredInSpan) {
            let before = previousInterval(of: period, now: now, calendar: calendar)
            summary.english = English(
                average: average,
                previous: before.flatMap { before in Self.average(measured.filter { within(before, $0.date) }) },
                proofreads: measuredInSpan.count,
                clean: measuredInSpan.filter { $0.changes == 0 }.count,
                weeks: weeks(of: measured, now: now, calendar: calendar)
            )
        }

        let dictatedInto = inSpan.compactMap(\.appName)
        let names = summary.everDictated ? dictatedInto : fixed.compactMap(\.appName)
        summary.apps = Dictionary(grouping: names.filter { !$0.isEmpty }, by: { $0 })
            .map { AppShare(name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }

        let first = [counts.first?.date, actions.first?.date].compactMap { $0 }.min() ?? now
        let (starts, length) = stepStarts(of: period, from: first, now: now, calendar: calendar)
        summary.stepLength = length
        summary.steps = starts.map { Step(start: $0) }
        for count in inSpan {
            guard let index = index(of: count.date, in: starts) else { continue }
            summary.steps[index].words += count.words
            summary.steps[index].seconds += count.duration
        }
        for action in fixed {
            if let index = index(of: action.date, in: starts) { summary.steps[index].fixes += 1 }
        }
        summary.todayStep = index(of: now, in: starts)

        summary.streak = streak(dates: counts.map(\.date) + actions.map(\.date), now: now, calendar: calendar)
        summary.countedSince = [counts.first?.date, actions.first?.date].compactMap { $0 }.min().map(calendar.startOfDay(for:))
        summary.map = map(counts: counts, fixed: actions.filter(\.applied), now: now, calendar: calendar)
        return summary
    }

    private static func map(counts: [DictationCount], fixed: [WritingAction], now: Date, calendar: Calendar) -> [[MapDay]] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let first = calendar.date(byAdding: .weekOfYear, value: -(mapWeekCount - 1), to: thisWeek)
        else { return [] }
        let starts = (0..<mapWeekCount * 7)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
            .filter { $0 <= now }
        var days = starts.map { MapDay(date: $0) }
        for count in counts {
            guard let index = index(of: count.date, in: starts) else { continue }
            days[index].words += count.words
            days[index].seconds += count.duration
        }
        for action in fixed {
            guard let index = index(of: action.date, in: starts) else { continue }
            days[index].fixes += 1
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    // MARK: Stretches of time

    /// Nil for all time.
    static func interval(of period: Period, now: Date, calendar: Calendar) -> DateInterval? {
        switch period {
        case .week: calendar.dateInterval(of: .weekOfYear, for: now)
        case .month: calendar.dateInterval(of: .month, for: now)
        case .all: nil
        }
    }

    static func previousInterval(of period: Period, now: Date, calendar: Calendar) -> DateInterval? {
        switch period {
        case .week:
            calendar.date(byAdding: .weekOfYear, value: -1, to: now).flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        case .month:
            calendar.date(byAdding: .month, value: -1, to: now).flatMap { calendar.dateInterval(of: .month, for: $0) }
        case .all:
            nil
        }
    }

    /// Every date counts when there is no interval, which is how all time is asked for.
    private static func within(_ interval: DateInterval?, _ date: Date) -> Bool {
        guard let interval else { return true }
        return interval.start <= date && date < interval.end
    }

    /// Where each step of the line begins: the days of the week or the month, or, for all time, the weeks since the
    /// first thing counted, and months once that is more than a year of weeks.
    private static func stepStarts(
        of period: Period, from first: Date, now: Date, calendar: Calendar
    ) -> ([Date], StepLength) {
        switch period {
        case .week, .month:
            guard let span = interval(of: period, now: now, calendar: calendar) else { return ([], .day) }
            var starts: [Date] = []
            var day = span.start
            while day < span.end, starts.count < 31 {
                starts.append(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return (starts, .day)
        case .all:
            guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
                  let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first)?.start
            else { return ([], .week) }
            let weeks = (calendar.dateComponents([.weekOfYear], from: firstWeek, to: thisWeek).weekOfYear ?? 0) + 1
            if weeks <= mostWeeks {
                // At least a couple of months of weeks, so a first week isn't a line with one point.
                let count = max(weeks, weekCount)
                let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
                return (starts, .week)
            }
            guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start,
                  let firstMonth = calendar.dateInterval(of: .month, for: first)?.start
            else { return ([], .month) }
            let months = (calendar.dateComponents([.month], from: firstMonth, to: thisMonth).month ?? 0) + 1
            let starts = (0..<months).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
            return (starts, .month)
        }
    }

    /// The step a date falls in: the last one that begins at or before it.
    private static func index(of date: Date, in starts: [Date]) -> Int? {
        guard let first = starts.first, date >= first else { return nil }
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= date { low = middle } else { high = middle - 1 }
        }
        return low
    }

    // MARK: Streak and writing

    private static func streak(dates: [Date], now: Date, calendar: Calendar) -> Streak {
        var streak = Streak()
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, from date: Date) -> Date? { calendar.date(byAdding: .day, value: offset, to: date) }

        streak.includesToday = days.contains(today)
        // Until today is over, yesterday's run still stands.
        var cursor = streak.includesToday ? today : day(-1, from: today)
        while let date = cursor, days.contains(date) {
            streak.days += 1
            cursor = day(-1, from: date)
        }

        var run = 0
        var previous: Date?
        for date in days.sorted() {
            if let previous, day(1, from: previous) == date { run += 1 } else { run = 1 }
            streak.longest = max(streak.longest, run)
            previous = date
        }

        if let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start {
            let first = calendar.startOfDay(for: weekStart)
            streak.week = (0..<7).map { offset in day(offset, from: first).map(days.contains) ?? false }
            streak.todayIndex = calendar.dateComponents([.day], from: first, to: today).day ?? 0
        }
        return streak
    }

    private static func weeks(of measured: [WritingAction], now: Date, calendar: Calendar) -> [Double?] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<weekCount).reversed().map { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek.start),
                  let week = calendar.dateInterval(of: .weekOfYear, for: start)
            else { return nil }
            return average(measured.filter { within(week, $0.date) })
        }
    }

    private static func average(_ proofreads: [WritingAction]) -> Double? {
        let changes = proofreads.compactMap(\.changes)
        guard !changes.isEmpty else { return nil }
        return Double(changes.reduce(0, +)) / Double(changes.count)
    }
}

/// The window's numbers, said in words.
enum HomeFormat {
    /// "41 min" or "2 h 5 min"; under a minute, "under a minute".
    static func spoken(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else { return seconds > 0 ? "under a minute" : "0 min" }
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Time saved as a number and its unit, for the large figure: minutes up to an hour, then hours.
    static func saved(minutes: Int) -> (value: String, unit: String) {
        guard minutes >= 60 else { return (minutes.formatted(), "min") }
        let hours = Double(minutes) / 60
        return (hours.formatted(.number.precision(.fractionLength(0...1))), "h")
    }

    /// "2.6×"
    static func times(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "×"
    }

    /// Changes per proofread, to one decimal.
    static func corrections(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func dictations(_ count: Int) -> String {
        count == 1 ? "1 dictation" : "\(count.formatted()) dictations"
    }

    static func pages(_ count: Int) -> String {
        count == 1 ? "about 1 page" : "about \(count.formatted()) pages"
    }

    static func days(_ count: Int) -> String { count == 1 ? "day" : "days" }

    /// How long one dictation took: "26 s" or "1 min 40 s".
    static func length(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return whole < 60 ? "\(whole) s" : "\(whole / 60) min \(whole % 60) s"
    }

    /// Under the large number of the first tile.
    static func heroDetail(_ summary: HomeSummary) -> String {
        var parts = [dictations(summary.dictations), spoken(summary.seconds)]
        if !summary.wideTiles.contains(.timeSaved), summary.minutesSaved >= 1 {
            let saved = saved(minutes: summary.minutesSaved)
            parts.append("about \(saved.value) \(saved.unit) saved")
        } else if summary.pages >= 1 {
            parts.append(pages(summary.pages))
        }
        return parts.joined(separator: " · ")
    }

    static func streakNote(_ streak: HomeSummary.Streak) -> String {
        // Short, so they fit beside the number in the narrowest window.
        if streak.days == 0 { return "Start today" }
        if !streak.includesToday { return "Keep it going" }
        if streak.days == 1, streak.longest <= 1 { return "Day one" }
        return streak.days >= streak.longest ? "Longest yet" : "Best: \(streak.longest.formatted()) days"
    }

    /// Which way the corrections go against the stretch before, where fewer is better.
    static func trend(_ english: HomeSummary.English, period: HomeSummary.Period) -> String? {
        guard let previous = english.previous else { return nil }
        let before = period == .month ? "last month" : "last week"
        if abs(english.average - previous) < 0.05 { return "the same as \(before)" }
        return "\(english.average < previous ? "down" : "up") from \(corrections(previous)) \(before)"
    }

    /// The words under the line of the first tile: every day of a week, a few days of a month, or the two ends
    /// of all time. Each says which step it sits under and whether that step is now.
    static func lineLabels(_ summary: HomeSummary, calendar: Calendar) -> [(step: Int, text: String, isNow: Bool)] {
        let steps = summary.steps
        guard !steps.isEmpty else { return [] }
        func format(_ style: Date.FormatStyle, _ date: Date) -> String {
            var style = style
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }
        switch (summary.period, summary.stepLength) {
        case (.week, _):
            return steps.enumerated().map { index, step in
                (index, format(.dateTime.weekday(.abbreviated), step.start), index == summary.todayStep)
            }
        case (.month, _):
            var shown = Set(stride(from: 0, to: steps.count, by: 7))
            if let today = summary.todayStep {
                // A number next to today's would run into it.
                shown = shown.filter { abs($0 - today) > 1 }
                shown.insert(today)
            }
            return shown.sorted().map { ($0, format(.dateTime.day(), steps[$0].start), $0 == summary.todayStep) }
        case (.all, .month):
            return [
                (0, format(.dateTime.month(.abbreviated).year(), steps[0].start), false),
                (steps.count - 1, "This month", true),
            ]
        case (.all, _):
            return [
                (0, format(.dateTime.day().month(.abbreviated), steps[0].start), false),
                (steps.count - 1, "This week", true),
            ]
        }
    }

    /// What pointing at a step of the first tile's line says: when it was, and what it held.
    static func lineStep(_ summary: HomeSummary, at index: Int, calendar: Calendar) -> (when: String, what: String) {
        guard summary.steps.indices.contains(index) else { return ("", "") }
        let step = summary.steps[index]
        var style: Date.FormatStyle
        switch summary.stepLength {
        case .day: style = .dateTime.weekday(.abbreviated).day().month(.abbreviated)
        case .week: style = .dateTime.day().month(.abbreviated)
        case .month: style = .dateTime.month(.abbreviated).year()
        }
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        let date = step.start.formatted(style)
        let when = summary.stepLength == .week ? "Week of \(date)" : date
        // Days of this week or month that haven't come yet have nothing to say.
        if summary.stepLength == .day, let today = summary.todayStep, index > today {
            return (when, "Still to come")
        }
        if summary.hero == .fixes {
            guard step.fixes > 0 else { return (when, "No fixes") }
            return (when, step.fixes == 1 ? "1 fix" : "\(step.fixes.formatted()) fixes")
        }
        guard step.words > 0 else { return (when, index == summary.todayStep ? "No words yet" : "No words") }
        let words = step.words == 1 ? "1 word" : "\(step.words.formatted()) words"
        return (when, step.minutesSaved >= 1 ? "\(words) · \(step.minutesSaved.formatted()) min saved" : words)
    }

    /// What pointing at a day of the year map says.
    static func mapDay(_ day: HomeSummary.MapDay, metric: HomeSummary.MapMetric, counted: Bool, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        let date = day.date.formatted(style)
        guard counted else { return "Not counted yet · \(date)" }
        switch metric {
        case .words:
            guard day.words > 0 else { return "No words · \(date)" }
            let words = day.words == 1 ? "1 word" : "\(day.words.formatted()) words"
            return day.minutesSaved >= 1 ? "\(words) · \(day.minutesSaved.formatted()) min saved · \(date)" : "\(words) · \(date)"
        case .fixes:
            guard day.fixes > 0 else { return "No fixes · \(date)" }
            return "\(day.fixes == 1 ? "1 fix" : "\(day.fixes.formatted()) fixes") · \(date)"
        }
    }

    /// The heading of a day of transcripts.
    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
        return date.formatted(style)
    }
}
