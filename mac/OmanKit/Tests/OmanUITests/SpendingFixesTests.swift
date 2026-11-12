import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

/// The Spending page's fixes: texts written and put back, beside what Claude cost.
@Suite struct SpendingFixesTests {
    private func makeCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Chisinau"))
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }

    private func action(
        _ date: Date, _ kind: WritingTask.Kind, app: String? = "Slack", applied: Bool = false
    ) -> WritingAction {
        WritingAction(date: date, kind: kind, model: "claude-haiku-5-5", appName: app, applied: applied)
    }

    private func entry(_ date: Date, _ cost: Double, _ kind: WritingTask.Kind?, model: String = "claude-haiku-5-5") -> UsageEntry {
        UsageEntry(date: date, model: model, tokens: TokenUsage(input: 100, output: 20), cost: cost, kind: kind)
    }

    @Test func eachBarCountsWhatWasWrittenPutBackAndSpent() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 11, 15)
        let actions = [
            action(try date(calendar, 11, 11, 9), .proofread, applied: true),
            action(try date(calendar, 11, 11, 10), .proofread, applied: true),
            action(try date(calendar, 11, 11, 11), .rewrite, app: "Mail"),
            action(try date(calendar, 11, 11, 12), .explain),
            action(try date(calendar, 11, 10, 12), .compose, applied: true),
        ]
        let entries = [
            entry(try date(calendar, 11, 11, 9), 0.002, .proofread),
            entry(try date(calendar, 11, 11, 11), 0.003, .rewrite, model: "claude-sonnet-5-5"),
            entry(try date(calendar, 11, 10, 12), 0.001, .compose),
        ]

        let week = SpendingSummary.make(from: entries, actions: actions, now: now, calendar: calendar)[.thisWeek]
        let wednesday = try #require(week.bars.first { calendar.isDate($0.start, inSameDayAs: now) })

        #expect(wednesday.written == 4)
        #expect(wednesday.fixes == 2)
        #expect(wednesday.kinds.map(\.kind) == [.proofread, .rewrite, .explain])
        #expect(wednesday.kinds.map(\.written) == [2, 1, 1])
        #expect(wednesday.requests == 2)
        #expect(abs(wednesday.cost - 0.005) < 1e-9)
        #expect(wednesday.models.map(\.name) == ["Sonnet 5.5", "Haiku 5.5"])
        #expect(wednesday.tokens == 240)
        #expect(!wednesday.isEmpty)

        #expect(week.written == 5)
        #expect(week.fixes == 3)
        #expect(week.kinds.map(\.kind) == [.proofread, .rewrite, .explain, .compose])
        #expect(abs((week.kinds.first { $0.kind == .rewrite }?.cost ?? 0) - 0.003) < 1e-9)
        #expect(week.apps.map(\.name) == ["Slack", "Mail"])
        #expect(week.apps.first?.fixes == 3)
        #expect(week.unsplitCost == 0)
    }

    @Test func requestsFromBeforeKindsWereKeptAreSpentButNotSplit() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 11, 15)
        let entries = [entry(try date(calendar, 11, 2, 9), 0.5, nil), entry(try date(calendar, 11, 3, 9), 0.25, .rewrite)]

        let month = SpendingSummary.make(from: entries, now: now, calendar: calendar)[.thisMonth]

        #expect(abs(month.cost - 0.75) < 1e-9)
        #expect(abs(month.unsplitCost - 0.5) < 1e-9)
        #expect(month.kinds.map(\.kind) == [.rewrite])
        #expect(month.fixes == 0)
    }

    @Test func fixesAloneCountAsSomethingToShow() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 11, 15)
        // Apple's model costs nothing, so its texts leave no spending behind.
        let actions = [action(try date(calendar, 5, 4, 9), .proofread, applied: true)]

        let summary = SpendingSummary.make(from: [], actions: actions, now: now, calendar: calendar)

        #expect(summary.hasEntries)
        // All time reaches back to the month of the oldest text.
        #expect(summary[.allTime].bars.first.map { calendar.component(.month, from: $0.start) } == 5)
        #expect(summary[.allTime].fixes == 1)
    }

    @Test func eachScaleEndsOnARoundNumberWithARoundMiddle() {
        #expect(SpendingSummary.countScale(for: 0) == 2)
        #expect(SpendingSummary.countScale(for: 3) == 4)
        #expect(SpendingSummary.countScale(for: 9) == 10)
        #expect(SpendingSummary.countScale(for: 37) == 40)
        #expect(SpendingSummary.countScale(for: 120) == 200)
        for largest in [0, 1, 5, 7, 11, 99, 1_234] {
            let scale = SpendingSummary.countScale(for: largest)
            #expect(scale >= max(largest, 2))
            #expect(scale % 2 == 0)
        }
        #expect(SpendingSummary.costScale(for: 0) == 0.01)
        #expect(abs(SpendingSummary.costScale(for: 0.003) - 0.01) < 1e-12)
        #expect(abs(SpendingSummary.costScale(for: 0.015) - 0.02) < 1e-12)
        #expect(abs(SpendingSummary.costScale(for: 0.023) - 0.03) < 1e-12)
        #expect(abs(SpendingSummary.costScale(for: 0.031) - 0.04) < 1e-12)
        #expect(abs(SpendingSummary.costScale(for: 0.045) - 0.05) < 1e-12)
        #expect(abs(SpendingSummary.costScale(for: 0.06) - 0.1) < 1e-12)
        #expect(abs(SpendingSummary.costScale(for: 1.3) - 2) < 1e-12)
    }

    @Test func barDetailsAreSaidInWords() throws {
        let calendar = try makeCalendar()
        let start = try date(calendar, 11, 11, 0)
        let bar = SpendingSummary.Bar(
            start: start,
            end: start.addingTimeInterval(86_400),
            cost: 0.0021,
            requests: 2,
            written: 3,
            fixes: 1,
            kinds: [
                .init(kind: .proofread, written: 2, fixes: 1),
                .init(kind: .rewrite, written: 1),
            ],
            models: [.init(name: "Claude Haiku", cost: 0.0015, requests: 1), .init(name: "Claude Sonnet", cost: 0.0006, requests: 1)]
        )
        #expect(SpendingFormat.fixes(1) == "1 fix put back")
        #expect(SpendingFormat.fixes(6) == "6 fixes put back")
        #expect(SpendingFormat.written(3) == "3 written")
        #expect(SpendingFormat.ofTextsWritten(1) == "of 1 text written")
        #expect(SpendingFormat.ofTextsWritten(4) == "of 4 texts written")
        #expect(SpendingFormat.kinds(bar.kinds) == "Proofread 2 · Rewrite 1")
        #expect(SpendingFormat.models(bar.models).contains("Claude Haiku"))
        #expect(SpendingFormat.precise(0.0021).filter(\.isNumber) == "00021")
        #expect(SpendingFormat.precise(1.5).filter(\.isNumber) == "150")
        #expect(!SpendingFormat.title(of: bar, in: .thisWeek).isEmpty)
        #expect(SpendingSettingsView.detail(of: .init(kind: .explain, written: 4)) == "4 written")
        #expect(SpendingSettingsView.detail(of: .init(kind: .rewrite, written: 4, fixes: 3)) == "4 written · 3 put back")
    }
}

/// The panel notes each text it writes, and when it is put back.
@MainActor
@Suite struct PanelActionTests {
    private let selection = SelectionCapture(app: Harness.slack, text: "hey can u send it")

    @Test func aRewriteIsNotedAndMarkedWhenReplaced() async throws {
        let harness = Harness()
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.rewrite()
        await panel.runningTask?.value

        let noted = try #require(harness.actions.recorded.first)
        #expect(harness.actions.recorded.count == 1)
        #expect(noted.kind == .rewrite)
        #expect(noted.appName == "Slack")
        #expect(noted.model == WritingModel.default.rawValue)
        #expect(!noted.applied)

        panel.applyResult()
        await panel.runningTask?.value
        #expect(harness.actions.recorded.first?.applied == true)
    }

    @Test func aChangeAskedForIsAnotherTextOfTheSameKind() async {
        let harness = Harness()
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.proofread()
        await panel.runningTask?.value
        panel.adjustment = "shorter"
        panel.applyAdjustment()
        await panel.runningTask?.value

        #expect(harness.actions.recorded.map(\.kind) == [.proofread, .proofread])
        panel.applyResult()
        await panel.runningTask?.value
        // Only the text that was put back counts as a fix.
        #expect(harness.actions.recorded.map(\.applied) == [false, true])
    }

    @Test func aFailedRequestNotesNothing() async {
        let harness = Harness()
        harness.writing.script(deltas: [], error: WritingError.network("offline"))
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.proofread()
        await panel.runningTask?.value

        #expect(panel.screen == .failed)
        #expect(harness.actions.recorded.isEmpty)
    }

    @Test func aStoreThatFailsLeavesTheResultAlone() async {
        let harness = Harness()
        harness.actions.fail(with: FakeFailure("disk is full"))
        let panel = harness.makePanel()
        panel.begin(with: selection)
        panel.explain()
        await panel.runningTask?.value

        #expect(panel.screen == .result)
        #expect(panel.draft == "Hello world")
    }

    @Test func thePageReadsTheTextsWritten() throws {
        let harness = Harness()
        let now = Date()
        harness.actions.seed([
            WritingAction(date: now.addingTimeInterval(-60), kind: .proofread, model: "apple-on-device", appName: "Mail", applied: true)
        ])
        let settings = harness.makeSettings()

        settings.reloadSpending(now: now)

        #expect(settings.spending[.today].fixes == 1)
        #expect(settings.spending[.today].apps.map(\.name) == ["Mail"])
        #expect(settings.spending.hasEntries)
    }
}
