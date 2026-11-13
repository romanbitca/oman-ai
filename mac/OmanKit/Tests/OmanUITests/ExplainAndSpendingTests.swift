import Foundation
import OmanCore
import Testing
@testable import OmanUI

@MainActor
@Suite struct ExplainTests {
    private let selection = SelectionCapture(app: Harness.slack, text: "can we move it to monday?")

    private func finish(_ model: PanelViewModel) async {
        await model.runningTask?.value
    }

    @Test func explainSendsTheSelectionWithItsContextButNoStyle() async throws {
        let harness = Harness()
        let saved = WritingStyle(name: "Slack", samples: [StyleSample(text: "yo")])
        harness.styles.seed([saved])
        try harness.styles.setLastStyleChoice(.style(saved.id), forApp: "com.tinyspeck.slackmacgap")
        let model = harness.makePanel()
        model.begin(with: selection)
        model.setIncludesMessages(true)
        model.contextText = "Lunch on Friday?"
        model.explain()
        await finish(model)

        let request = try #require(harness.writing.requests.last)
        #expect(request.task == .explain(text: "can we move it to monday?"))
        #expect(request.style == nil)
        #expect(request.context.pastedText == "Lunch on Friday?")
        #expect(model.screen == .result)
        #expect(model.draft == "Hello world")
    }

    @Test func anExplanationCanBeReadButIsNeverPasted() async {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.explain()
        await finish(model)

        #expect(model.isOnlyToRead)
        #expect(model.canApplyResult == false)
        #expect(model.originalText == "can we move it to monday?")

        model.applyResult()
        await finish(model)
        #expect(harness.system.replaceCalls.isEmpty)
        #expect(harness.system.insertCalls.isEmpty)
        #expect(harness.presenter.hideCount == 0)
        // ⌘↩ is left alone instead of pasting.
        #expect(model.handlePanelShortcut(KeyCombo(keyCode: 36, modifiers: KeyCombo.command)) == false)
    }

    @Test func tryAgainAsksForAFreshReading() async throws {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.explain()
        await finish(model)
        let first = try #require(harness.writing.requests.last)

        model.tryAgain()
        await finish(model)

        #expect(harness.writing.requests.count == 2)
        #expect(harness.writing.requests.last == first)
        #expect(harness.writing.requests.last?.refinement == nil)
    }

    @Test func anExplanationTakesNoAdjustment() async {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.explain()
        await finish(model)

        model.adjustment = "more detail"
        model.applyAdjustment()
        await finish(model)

        #expect(harness.writing.requests.count == 1)
    }

    @Test func theExplainShortcutRunsOnTheSelection() async {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: selection)
        model.run(.explain)
        await finish(model)

        #expect(harness.writing.requests.last?.task == .explain(text: "can we move it to monday?"))
    }

    @Test func explainNeedsASelection() {
        let harness = Harness()
        let model = harness.makePanel()
        model.begin(with: SelectionCapture(app: Harness.slack, text: nil))
        model.explain()

        #expect(harness.writing.requests.isEmpty)
    }

    @Test func theShortcutIsStoredAndNamed() {
        #expect(ShortcutAction(storageKey: "explain") == .explain)
        #expect(ShortcutAction.explain.isGlobal)
        #expect(Harness().makeSettings().title(for: .explain) == "Explain selection")
    }
}

@Suite struct SpendingSummaryTests {
    private typealias Period = SpendingSummary.Period

    private func makeCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // Summer time ended on 25 October 2026 here, inside last month.
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Chisinau"))
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, year: Int = 2026) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    private func entry(_ date: Date, _ cost: Double, model: String = "claude-haiku-5-5", tokens: TokenUsage = TokenUsage(input: 1)) -> UsageEntry {
        UsageEntry(date: date, model: model, tokens: tokens, cost: cost)
    }

    private func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1e-9
    }

    /// A Wednesday afternoon. The week started on Monday 9 November.
    private func sample(_ calendar: Calendar) throws -> (now: Date, entries: [UsageEntry]) {
        (
            try date(calendar, 11, 11, 15),
            [
                entry(try date(calendar, 9, 1, 12), 5),
                entry(try date(calendar, 10, 20, 12), 1),
                entry(try date(calendar, 11, 8, 22), 0.4),
                entry(try date(calendar, 11, 9, 0, 10), 0.05),
                entry(try date(calendar, 11, 10, 23, 30), 0.1),
                entry(try date(calendar, 11, 11, 9), 0.02),
                entry(try date(calendar, 11, 11, 14), 0.03),
            ]
        )
    }

    @Test func eachPeriodCountsOnlyWhatFallsInsideIt() throws {
        let calendar = try makeCalendar()
        let (now, entries) = try sample(calendar)

        let summary = SpendingSummary.make(from: entries, now: now, calendar: calendar)

        #expect(close(summary[.today].cost, 0.05))
        #expect(summary[.today].requests == 2)
        #expect(close(summary[.thisWeek].cost, 0.2))
        #expect(summary[.thisWeek].requests == 4)
        #expect(close(summary[.thisMonth].cost, 0.6))
        #expect(summary[.thisMonth].requests == 5)
        #expect(close(summary[.lastMonth].cost, 1))
        #expect(summary[.lastMonth].requests == 1)
        #expect(close(summary[.allTime].cost, 6.6))
        #expect(summary[.allTime].requests == 7)
        #expect(summary.hasEntries)
    }

    @Test func todayIsDrawnByTheHour() throws {
        let calendar = try makeCalendar()
        let (now, entries) = try sample(calendar)

        let bars = SpendingSummary.make(from: entries, now: now, calendar: calendar)[.today].bars

        #expect(bars.count == 24)
        #expect(bars.first?.start == calendar.startOfDay(for: now))
        // A label goes under the middle of its bar.
        #expect(bars.first?.middle == calendar.startOfDay(for: now).addingTimeInterval(1800))
        #expect(bars.last?.end == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        #expect(close(bars[9].cost, 0.02))
        #expect(close(bars[14].cost, 0.03))
        #expect(close(bars.reduce(0) { $0 + $1.cost }, 0.05))
    }

    @Test func weeksAndMonthsAreDrawnByTheDayIncludingDaysStillToCome() throws {
        let calendar = try makeCalendar()
        let (now, entries) = try sample(calendar)
        let summary = SpendingSummary.make(from: entries, now: now, calendar: calendar)

        let week = summary[.thisWeek].bars
        #expect(week.first?.start == calendar.startOfDay(for: try date(calendar, 11, 9, 12)))
        #expect(week.map(\.cost).elementsEqual([0.05, 0.1, 0.05, 0, 0, 0, 0], by: close))

        let month = summary[.thisMonth].bars
        #expect(month.count == 30)
        #expect(close(month[7].cost, 0.4))

        // October 2026 is an hour longer here, and still has 31 days of one bar each.
        let lastMonth = summary[.lastMonth].bars
        #expect(lastMonth.count == 31)
        #expect(lastMonth.first?.start == calendar.startOfDay(for: try date(calendar, 10, 1, 12)))
        #expect(close(lastMonth[19].cost, 1))
    }

    @Test func allTimeIsDrawnByTheMonthAndShowsAtLeastHalfAYear() throws {
        let calendar = try makeCalendar()
        let (now, entries) = try sample(calendar)

        let bars = SpendingSummary.make(from: entries, now: now, calendar: calendar)[.allTime].bars

        #expect(bars.count == SpendingSummary.minimumMonths)
        #expect(bars.first?.start == calendar.startOfDay(for: try date(calendar, 6, 1, 12)))
        #expect(bars.map(\.cost).elementsEqual([0, 0, 0, 5, 1, 0.6], by: close))
    }

    @Test func allTimeReachesBackToTheFirstRequest() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 11, 15)
        let entries = [entry(try date(calendar, 1, 20, 12, year: 2025), 2), entry(try date(calendar, 11, 2, 12), 1)]

        let allTime = SpendingSummary.make(from: entries, now: now, calendar: calendar)[.allTime]

        #expect(allTime.bars.count == 23)
        #expect(close(allTime.bars.first?.cost ?? 0, 2))
        #expect(close(allTime.bars.last?.cost ?? 0, 1))
        #expect(close(allTime.cost, 3))
    }

    @Test func nothingSpentStillGivesEveryBar() throws {
        let calendar = try makeCalendar()
        let summary = SpendingSummary.make(from: [], now: try date(calendar, 11, 11, 15), calendar: calendar)

        #expect(summary[.today].bars.count == 24)
        #expect(summary[.thisWeek].bars.count == 7)
        #expect(summary[.thisMonth].bars.count == 30)
        #expect(summary[.lastMonth].bars.count == 31)
        #expect(summary[.allTime].bars.count == SpendingSummary.minimumMonths)
        for period in Period.allCases {
            #expect(summary[period].bars.allSatisfy { $0.cost == 0 })
            #expect(summary[period].cost == 0)
            #expect(summary[period].requests == 0)
            #expect(summary[period].averageCost == 0)
            #expect(summary[period].models.isEmpty)
        }
        #expect(!summary.hasEntries)
    }

    @Test func modelsKeepOneListInEveryPeriodMostExpensiveFirst() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 11, 15)
        let entries = [
            entry(try date(calendar, 10, 20, 12), 1, model: "claude-opus-5-5"),
            // Anthropic may name the model that answered with a date after it.
            entry(try date(calendar, 11, 11, 9), 0.1, model: "claude-haiku-5-5-20261001"),
            entry(try date(calendar, 11, 11, 10), 0.2, model: "claude-haiku-5-5"),
            entry(try date(calendar, 11, 10, 9), 0.05, model: "claude-next-9"),
        ]

        let summary = SpendingSummary.make(from: entries, now: now, calendar: calendar)

        #expect(summary[.allTime].models.map(\.name) == ["Opus 5.5", "Haiku 5.5", "claude-next-9"])
        let today = summary[.today].models
        #expect(today.map(\.name) == ["Opus 5.5", "Haiku 5.5", "claude-next-9"])
        #expect(today.map(\.requests) == [0, 2, 0])
        #expect(today.map(\.cost).elementsEqual([0, 0.3, 0], by: close))
        #expect(summary[.lastMonth].models.map(\.requests) == [1, 0, 0])
    }

    @Test func tokensAndTheAverageComeFromThePeriodsRequests() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 11, 15)
        let entries = [
            entry(try date(calendar, 11, 11, 9), 0.03, tokens: TokenUsage(input: 100, output: 20, cacheRead: 400)),
            entry(try date(calendar, 11, 11, 10), 0.01, tokens: TokenUsage(input: 50, output: 30, cacheWrite1h: 200)),
            entry(try date(calendar, 10, 2, 10), 9, tokens: TokenUsage(input: 1_000_000)),
        ]

        let today = SpendingSummary.make(from: entries, now: now, calendar: calendar)[.today]

        #expect(today.tokens == 800)
        #expect(close(today.averageCost, 0.02))
    }

    @Test func onlyAsManyBarsAreLabelledAsFit() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 11, 15)
        let entries = [entry(try date(calendar, 1, 20, 12, year: 2025), 2)]
        let summary = SpendingSummary.make(from: entries, now: now, calendar: calendar)
        func labels(_ period: Period) -> [Date] {
            SpendingSummary.labelledBars(summary[period].bars, for: period).map(\.start)
        }

        #expect(labels(.today).map { calendar.component(.hour, from: $0) } == [0, 6, 12, 18])
        #expect(labels(.thisWeek).count == 7)
        #expect(labels(.thisMonth).map { calendar.component(.day, from: $0) } == [1, 8, 15, 22, 29])
        // 23 months: every third one, counted back from this month.
        let months = labels(.allTime)
        #expect(months.count == 8)
        #expect(months.last == summary[.allTime].bars.last?.start)
    }

    @Test func smallAmountsDoNotReadAsNothing() {
        let format = { (dollars: Double) in SpendingFormat.amount(dollars).filter { $0.isNumber || $0 == "<" } }
        #expect(format(0) == "000")
        #expect(format(0.004) == "<001")
        #expect(format(0.256) == "026")
    }

    @Test func anAverageKeepsFractionsOfACent() {
        let digits = { (dollars: Double) in SpendingFormat.average(dollars).filter(\.isNumber) }
        #expect(digits(0.0042) == "00042")
        #expect(digits(0.25) == "025")
        #expect(SpendingFormat.requests(1) == "1 request")
        #expect(SpendingFormat.requests(12).hasSuffix("requests"))
    }
}

@MainActor
@Suite struct SpendingSettingsTests {
    @Test func reloadReadsEverythingBecauseThePageShowsAllTime() throws {
        let harness = Harness()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        harness.usage.seed([
            UsageEntry(date: now.addingTimeInterval(-60), model: "claude-opus-5-5", tokens: TokenUsage(input: 1), cost: 0.25),
            UsageEntry(date: now.addingTimeInterval(-86_400 * 400), model: "claude-opus-5-5", tokens: TokenUsage(input: 1), cost: 1),
        ])
        let model = harness.makeSettings()

        model.reloadSpending(now: now, calendar: calendar)

        #expect(harness.usage.since == .distantPast)
        #expect(model.spending[.today].cost == 0.25)
        #expect(model.spending[.allTime].cost == 1.25)
        #expect(model.spendingError == nil)
    }

    @Test func aStoreFailureIsShownAndTheLastSummaryKept() throws {
        let harness = Harness()
        let model = harness.makeSettings()
        harness.usage.fail(with: FakeFailure("disk is full"))

        model.reloadSpending()

        #expect(model.spendingError == "disk is full")
        #expect(!model.spending.hasEntries)
    }
}
