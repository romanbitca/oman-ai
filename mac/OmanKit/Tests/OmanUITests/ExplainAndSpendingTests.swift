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
        try harness.styles.setLastStyleID(saved.id, forBundleID: "com.tinyspeck.slackmacgap")
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

        #expect(model.isExplanation)
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
    private func makeCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // Summer time ended on 25 October 2026 here, inside the weeks shown.
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Chisinau"))
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)))
    }

    private func entry(_ date: Date, _ cost: Double) -> UsageEntry {
        UsageEntry(date: date, model: "claude-haiku-5-5", tokens: TokenUsage(input: 1), cost: cost)
    }

    private func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1e-9
    }

    @Test func groupsSpendingIntoDaysAndWeeksThatEndToday() throws {
        let calendar = try makeCalendar()
        // A Wednesday. The week started on Monday 9 November.
        let now = try date(calendar, 11, 11, 15)
        let entries = [
            entry(try date(calendar, 9, 1, 12), 5),
            entry(try date(calendar, 10, 20, 12), 1),
            entry(try date(calendar, 11, 8, 22), 0.4),
            entry(try date(calendar, 11, 9, 0, 10), 0.05),
            entry(try date(calendar, 11, 10, 23, 30), 0.1),
            entry(try date(calendar, 11, 11, 9), 0.02),
            entry(try date(calendar, 11, 11, 14), 0.03),
        ]

        let summary = SpendingSummary.make(from: entries, now: now, calendar: calendar)

        #expect(summary.days.count == 14)
        #expect(summary.days.last?.start == calendar.startOfDay(for: now))
        #expect(summary.days.first?.start == calendar.startOfDay(for: try date(calendar, 10, 29, 12)))
        #expect(summary.days.suffix(4).map(\.cost).elementsEqual([0.4, 0.05, 0.1, 0.05], by: close))
        #expect(close(summary.today, 0.05))

        #expect(summary.weeks.count == 8)
        #expect(summary.weeks.last?.start == calendar.startOfDay(for: try date(calendar, 11, 9, 12)))
        #expect(summary.weeks.first?.start == calendar.startOfDay(for: try date(calendar, 9, 21, 12)))
        #expect(summary.weeks.map(\.cost).elementsEqual([0, 0, 0, 0, 1, 0, 0.4, 0.2], by: close))
        #expect(close(summary.thisWeek, 0.2))
        #expect(summary.hasEntries)
    }

    @Test func loadsOnlyFromTheOldestWeekShown() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 11, 15)

        let earliest = SpendingSummary.earliestDate(now: now, calendar: calendar)

        #expect(earliest == SpendingSummary.make(from: [], now: now, calendar: calendar).weeks.first?.start)
    }

    @Test func nothingSpentStillGivesEveryBar() throws {
        let calendar = try makeCalendar()
        let summary = SpendingSummary.make(from: [], now: try date(calendar, 11, 11, 15), calendar: calendar)

        #expect(summary.days.count == 14)
        #expect(summary.weeks.count == 8)
        #expect(summary.days.allSatisfy { $0.cost == 0 })
        #expect(summary.today == 0)
        #expect(summary.thisWeek == 0)
        #expect(!summary.hasEntries)
    }

    @Test func smallAmountsDoNotReadAsNothing() {
        let format = { (dollars: Double) in SpendingFormat.amount(dollars).filter { $0.isNumber || $0 == "<" } }
        #expect(format(0) == "000")
        #expect(format(0.004) == "<001")
        #expect(format(0.256) == "026")
    }
}

@MainActor
@Suite struct SpendingSettingsTests {
    @Test func reloadReadsFromTheOldestWeekShown() throws {
        let harness = Harness()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        harness.usage.seed([
            UsageEntry(date: now.addingTimeInterval(-60), model: "claude-opus-5-5", tokens: TokenUsage(input: 1), cost: 0.25),
        ])
        let model = harness.makeSettings()

        model.reloadSpending(now: now, calendar: calendar)

        #expect(harness.usage.since == SpendingSummary.earliestDate(now: now, calendar: calendar))
        #expect(model.spending.today == 0.25)
        #expect(model.spending.thisWeek == 0.25)
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
