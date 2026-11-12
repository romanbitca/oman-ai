import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

/// The Lab's numbers, from what OmanAI keeps.
@Suite struct LabSummaryTests {
    private func makeCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Chisinau"))
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int = 12) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
    }

    private func dictation(_ date: Date, _ text: String, seconds: TimeInterval = 30) -> SavedDictation {
        SavedDictation(date: date, text: text, duration: seconds, model: "apple", language: nil, appName: "Slack")
    }

    private func proofread(_ date: Date, changes: Int?, applied: Bool = true) -> WritingAction {
        WritingAction(date: date, kind: .proofread, model: "claude-haiku-5-5", appName: "Mail", applied: applied, changes: changes)
    }

    @Test func itCountsWhatWasDictatedFixedAndSpent() throws {
        let calendar = try makeCalendar()
        // A Thursday; the week began on Monday 9 November.
        let now = try date(calendar, 11, 12, 15)
        let summary = LabSummary.make(
            dictations: [
                dictation(try date(calendar, 11, 12), "Ship the beta on Monday", seconds: 90),
                dictation(try date(calendar, 11, 2), "Hello there", seconds: 3_600),
            ],
            actions: [
                proofread(try date(calendar, 11, 12), changes: 2),
                WritingAction(date: try date(calendar, 11, 10), kind: .rewrite, model: "claude-haiku-5-5", appName: "Slack"),
                proofread(try date(calendar, 11, 3), changes: 4, applied: false),
            ],
            usage: [
                UsageEntry(date: try date(calendar, 11, 12), model: "claude-haiku-5-5", tokens: TokenUsage(input: 1), cost: 0.25),
                UsageEntry(date: try date(calendar, 10, 20), model: "claude-haiku-5-5", tokens: TokenUsage(input: 1), cost: 1),
            ],
            now: now,
            calendar: calendar
        )

        #expect(summary.dictations == 2)
        #expect(summary.dictationsThisWeek == 1)
        #expect(summary.wordsDictated == 7)
        #expect(summary.secondsDictated == 3_690)
        #expect(summary.fixes == 1)
        #expect(summary.fixesThisWeek == 1)
        #expect(summary.written == 3)
        #expect(summary.spentThisMonth == 0.25)
        #expect(summary.spentInAll == 1.25)
        #expect(summary.days.count == LabSummary.dayCount)
        #expect(summary.days.last?.dictations == 1)
        #expect(summary.days.last?.fixes == 1)
        #expect(summary.days.first.map { calendar.isDate($0.start, inSameDayAs: try! date(calendar, 10, 30)) } == true)
    }

    @Test func proofreadsShowHowTheWritingGoesWeekByWeek() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 12, 15)
        let actions = [
            // This week: 1 and 0 changes.
            proofread(try date(calendar, 11, 10), changes: 1),
            proofread(try date(calendar, 11, 11), changes: 0),
            // Last week: 3 and 2.
            proofread(try date(calendar, 11, 3), changes: 3),
            proofread(try date(calendar, 11, 4), changes: 2),
            // From before changes were counted, and not a proofread: left out.
            proofread(try date(calendar, 11, 5), changes: nil),
            WritingAction(date: try date(calendar, 11, 5), kind: .rewrite, model: "x", appName: nil, changes: nil),
        ]
        let summary = LabSummary.make(dictations: [], actions: actions, usage: [], now: now, calendar: calendar)

        #expect(summary.proofreads == 4)
        #expect(summary.cleanProofreads == 1)
        #expect(summary.cleanShare == 0.25)
        #expect(summary.changesThisWeek == 0.5)
        #expect(summary.changesLastWeek == 2.5)
        #expect(summary.weeks.count == LabSummary.weekCount)
        #expect(summary.weeks.last?.changesPerProofread == 0.5)
        #expect(summary.weeks.dropLast().last?.changesPerProofread == 2.5)
        #expect(summary.weeks.first?.changesPerProofread == nil)
        #expect(LabFormat.trend(thisWeek: summary.changesThisWeek, lastWeek: summary.changesLastWeek)?.hasSuffix("fewer than last week") == true)
    }

    @Test func numbersAreSaidInWords() {
        #expect(LabFormat.spoken(0) == "0 min")
        #expect(LabFormat.spoken(20) == "under a minute")
        #expect(LabFormat.spoken(2_460) == "41 min")
        #expect(LabFormat.spoken(7_500) == "2 h 5 min")
        #expect(LabFormat.spoken(7_200) == "2 h")
        #expect(LabFormat.trend(thisWeek: 1, lastWeek: 1.02) == "The same as last week")
        #expect(LabFormat.trend(thisWeek: 2, lastWeek: 1)?.hasSuffix("more than last week") == true)
        #expect(LabFormat.trend(thisWeek: nil, lastWeek: 1) == nil)
        #expect(LabSummary.words(in: " two  words\nthree ") == 3)
    }
}

@MainActor
@Suite struct LabModelTests {
    private func dictation(_ seconds: TimeInterval, _ text: String, app: String? = nil) -> SavedDictation {
        SavedDictation(date: Date(timeIntervalSince1970: seconds), text: text, duration: 2, model: "apple", language: nil, appName: app)
    }

    @Test func transcriptsCanBeFoundCopiedAndDeleted() {
        let harness = Harness()
        let older = dictation(1, "Older words", app: "Mail")
        let newer = dictation(2, "Newer words")
        harness.dictations.seed([older, newer])
        let lab = LabViewModel(services: harness.services)
        lab.reload()
        #expect(lab.transcripts.map(\.text) == ["Newer words", "Older words"])

        lab.search = "mail"
        #expect(lab.shownTranscripts.map(\.text) == ["Older words"])
        lab.search = "words"
        #expect(lab.shownTranscripts.count == 2)
        lab.search = ""

        lab.copy(older)
        #expect(harness.system.copied == ["Older words"])
        #expect(lab.copiedID == older.id)

        lab.delete(id: newer.id)
        #expect(lab.transcripts.map(\.text) == ["Older words"])

        lab.deleteAll()
        #expect(lab.transcripts.isEmpty)
    }

    @Test func keepingFewerTranscriptsDeletesTheOldestAtOnce() {
        let harness = Harness()
        harness.dictations.seed((0..<14).map { dictation(TimeInterval($0), "Said \($0)") })
        let lab = LabViewModel(services: harness.services)
        lab.reload()

        #expect(lab.transcriptsDeleted(by: .all) == 0)
        #expect(lab.transcriptsDeleted(by: .last50) == 0)
        #expect(lab.transcriptsDeleted(by: .last10) == 4)
        // None stops keeping more, and leaves the ones there are.
        #expect(lab.transcriptsDeleted(by: .off) == 0)

        lab.setHistory(.last10)
        #expect(lab.transcripts.count == 10)
        #expect(lab.transcripts.first?.text == "Said 13")
        #expect(lab.history == .last10)
        #expect((try? harness.settings.preferences())?.dictationHistory == .last10)

        lab.setHistory(.off)
        #expect(lab.transcripts.count == 10)
    }

    @Test func aProofreadNotesHowManyPlacesItChanged() async {
        let harness = Harness()
        harness.writing.script(deltas: ["Hello world"])
        let panel = harness.makePanel()
        panel.begin(with: SelectionCapture(app: Harness.slack, text: "Helo wrld"))
        panel.proofread()
        await panel.runningTask?.value
        panel.rewrite()
        await panel.runningTask?.value

        let noted = harness.actions.recorded
        #expect(noted.map(\.kind) == [.proofread, .rewrite])
        #expect(noted.first?.changes == 2)
        #expect(noted.last?.changes == nil)
    }
}
