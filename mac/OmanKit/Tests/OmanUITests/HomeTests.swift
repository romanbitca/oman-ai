import AppKit
import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

/// The numbers in OmanAI's own window, from what it counts.
@Suite struct HomeSummaryTests {
    private func makeCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Chisinau"))
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int = 12, year: Int = 2026) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func said(_ date: Date, words: Int, seconds: TimeInterval = 30, app: String? = "Slack") -> DictationCount {
        DictationCount(date: date, words: words, duration: seconds, appName: app)
    }

    private func proofread(_ date: Date, changes: Int?, applied: Bool = true, app: String? = "Mail") -> WritingAction {
        WritingAction(date: date, kind: .proofread, model: "claude-haiku-5-5", appName: app, applied: applied, changes: changes)
    }

    private func summary(
        _ period: HomeSummary.Period, counts: [DictationCount] = [], actions: [WritingAction] = [], now: Date, _ calendar: Calendar
    ) -> HomeSummary {
        HomeSummary.make(
            counts: counts.sorted { $0.date < $1.date }, actions: actions.sorted { $0.date < $1.date },
            period: period, now: now, calendar: calendar
        )
    }

    @Test func aStretchCountsWhatWasDictatedInIt() throws {
        let calendar = try makeCalendar()
        // A Thursday; the week began on Monday 9 November.
        let now = try date(calendar, 11, 12, 15)
        let counts = [
            said(try date(calendar, 11, 12), words: 120, seconds: 60),
            said(try date(calendar, 11, 2), words: 40, seconds: 30),
            said(try date(calendar, 10, 20), words: 10, seconds: 10),
        ]

        let week = summary(.week, counts: counts, now: now, calendar)
        #expect(week.dictations == 1)
        #expect(week.words == 120)
        #expect(week.seconds == 60)

        let month = summary(.month, counts: counts, now: now, calendar)
        #expect(month.dictations == 2)
        #expect(month.words == 160)

        let all = summary(.all, counts: counts, now: now, calendar)
        #expect(all.dictations == 3)
        #expect(all.words == 170)
        #expect(all.seconds == 100)
    }

    @Test func speedPagesAndTimeSavedComeFromWordsAndSeconds() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 12, 15)

        let quick = summary(.week, counts: [said(now, words: 1_100, seconds: 600)], now: now, calendar)
        #expect(quick.speed == 110)
        #expect(quick.timesFasterThanTyping == 2.75)
        // Typing 1,100 words at 40 a minute takes 27.5 minutes; speaking them took 10.
        #expect(quick.minutesSaved == 18)
        #expect(quick.pages == 4)

        let slow = summary(.week, counts: [said(now, words: 30, seconds: 60)], now: now, calendar)
        #expect(slow.speed == 30)
        #expect(slow.timesFasterThanTyping == nil)
        #expect(slow.minutesSaved == 0)

        let nothing = summary(.week, now: now, calendar)
        #expect(nothing.speed == nil)
        #expect(nothing.minutesSaved == 0)
        #expect(nothing.pages == 0)
    }

    @Test func theLineHasAStepForEachDayOrWeek() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 12, 15)
        let counts = [
            said(try date(calendar, 11, 12, 9), words: 120),
            said(try date(calendar, 11, 12, 14), words: 30),
            said(try date(calendar, 11, 10), words: 7),
            said(try date(calendar, 10, 20), words: 10),
        ]
        let fix = WritingAction(date: try date(calendar, 11, 11), kind: .rewrite, model: "x", appName: "Mail", applied: true)

        let week = summary(.week, counts: counts, actions: [fix], now: now, calendar)
        #expect(week.stepLength == .day)
        #expect(week.steps.map(\.words) == [0, 7, 0, 150, 0, 0, 0])
        #expect(week.steps.map(\.fixes) == [0, 0, 1, 0, 0, 0, 0])
        #expect(week.todayStep == 3)
        #expect(week.steps.first.map { calendar.isDate($0.start, inSameDayAs: try! date(calendar, 11, 9)) } == true)

        let month = summary(.month, counts: counts, now: now, calendar)
        #expect(month.steps.count == 30)
        #expect(month.todayStep == 11)
        #expect(month.steps[9].words == 7)

        // All time is cut into weeks, and never fewer than eight, so a first week isn't one point.
        let all = summary(.all, counts: counts, now: now, calendar)
        #expect(all.stepLength == .week)
        #expect(all.steps.count == HomeSummary.weekCount)
        #expect(all.todayStep == HomeSummary.weekCount - 1)
        #expect(all.steps.last?.words == 157)
        #expect(all.steps.reduce(0) { $0 + $1.words } == 167)

        // More than a year of weeks is cut into months.
        let long = summary(.all, counts: counts + [said(try date(calendar, 3, 3, year: 2024), words: 5)], now: now, calendar)
        #expect(long.stepLength == .month)
        #expect(long.steps.count == 33)
        #expect(long.steps.first?.words == 5)
        #expect(long.steps.last?.words == 157)
    }

    @Test func aStreakCountsDaysInARow() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 12, 15)
        let run = [
            said(try date(calendar, 11, 10), words: 1),
            said(try date(calendar, 11, 11), words: 1),
            said(try date(calendar, 11, 12, 9), words: 1),
        ]
        // The weekend before, with Monday missed, was written rather than dictated: it counts as use all the same.
        let earlier = [
            WritingAction(date: try date(calendar, 11, 7), kind: .rewrite, model: "x", appName: nil),
            WritingAction(date: try date(calendar, 11, 8), kind: .explain, model: "x", appName: nil),
        ]

        let streak = summary(.week, counts: run, actions: earlier, now: now, calendar).streak
        #expect(streak.days == 3)
        #expect(streak.includesToday)
        #expect(streak.longest == 3)
        #expect(streak.week == [false, true, true, true, false, false, false])
        #expect(streak.todayIndex == 3)
        #expect(HomeFormat.streakNote(streak) == "Longest yet")

        // Until today is over, yesterday's run still stands.
        let waiting = summary(.week, counts: Array(run.dropLast()), now: now, calendar).streak
        #expect(waiting.days == 2)
        #expect(!waiting.includesToday)
        #expect(HomeFormat.streakNote(waiting) == "Keep it going")

        let broken = summary(.week, counts: [run[0]], actions: earlier, now: now, calendar).streak
        #expect(broken.days == 0)
        #expect(broken.longest == 2)
        #expect(HomeFormat.streakNote(broken) == "Start today")

        let first = summary(.week, counts: [run[2]], now: now, calendar).streak
        #expect(first.days == 1)
        #expect(HomeFormat.streakNote(first) == "Day one")

        let shorter = summary(.week, counts: [run[2]], actions: earlier, now: now, calendar).streak
        #expect(HomeFormat.streakNote(shorter) == "Best: 2 days")
    }

    @Test func fixesAreSplitByKindAndProofreadsShowHowTheWritingGoes() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 12, 15)
        let actions = [
            // This week: 1 and 0 changes, both put back.
            proofread(try date(calendar, 11, 10), changes: 1),
            proofread(try date(calendar, 11, 11), changes: 0),
            WritingAction(date: try date(calendar, 11, 11), kind: .rewrite, model: "x", appName: "Slack", applied: true),
            WritingAction(date: try date(calendar, 11, 11), kind: .compose, model: "x", appName: "Slack", applied: false),
            WritingAction(date: try date(calendar, 11, 11), kind: .explain, model: "x", appName: "Slack"),
            // Last week: 3 and 2.
            proofread(try date(calendar, 11, 3), changes: 3),
            proofread(try date(calendar, 11, 4), changes: 2, applied: false),
            // From before changes were counted: no part of the average.
            proofread(try date(calendar, 11, 5), changes: nil),
            // Last month.
            proofread(try date(calendar, 10, 14), changes: 6),
        ]

        let week = summary(.week, actions: actions, now: now, calendar)
        #expect(week.fixes == HomeSummary.Fixes(proofread: 2, rewritten: 1, composed: 0))
        #expect(week.fixes.total == 3)
        let english = try #require(week.english)
        #expect(english.average == 0.5)
        #expect(english.previous == 2.5)
        #expect(english.proofreads == 2)
        #expect(english.clean == 1)
        #expect(english.weeks.count == HomeSummary.weekCount)
        #expect(english.weeks.last == 0.5)
        #expect(english.weeks.dropLast().last == 2.5)
        #expect(english.weeks.first == .some(nil))
        #expect(HomeFormat.trend(english, period: .week) == "down from \(HomeFormat.corrections(2.5)) last week")

        let month = summary(.month, actions: actions, now: now, calendar)
        #expect(month.fixes.proofread == 4)
        #expect(month.english?.average == 1.5)
        #expect(month.english?.previous == 6)
        #expect(month.english.flatMap { HomeFormat.trend($0, period: .month) }?.hasSuffix("last month") == true)

        let all = summary(.all, actions: actions, now: now, calendar)
        #expect(all.english?.average == 2.4)
        #expect(all.english?.previous == nil)
        #expect(all.english.flatMap { HomeFormat.trend($0, period: .all) } == nil)

        // A week with no proofread has nothing to say about the writing, though earlier ones were measured.
        let quiet = summary(.week, actions: Array(actions.dropFirst(5)), now: now, calendar)
        #expect(quiet.english == nil)
        #expect(quiet.everMeasured)
    }

    @Test func appsAreRankedByHowMuchWentIntoThem() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 12, 15)
        let counts = [
            said(now, words: 1, app: "Slack"), said(now, words: 1, app: "Mail"), said(now, words: 1, app: "Slack"),
            said(now, words: 1, app: "Claude"), said(now, words: 1, app: nil), said(now, words: 1, app: ""),
            said(try date(calendar, 10, 1), words: 1, app: "Notes"),
        ]
        let week = summary(.week, counts: counts, now: now, calendar)
        #expect(week.apps == [.init(name: "Slack", count: 2), .init(name: "Claude", count: 1), .init(name: "Mail", count: 1)])

        // Someone who never dictates sees where their fixes went instead.
        let fixes = summary(.week, actions: [proofread(now, changes: 1, app: "Mail"), proofread(now, changes: 1, applied: false, app: "Notes")], now: now, calendar)
        #expect(fixes.apps == [.init(name: "Mail", count: 1)])
    }

    @Test func aStepOfTheLineSaysWhenItWasAndWhatItHeld() throws {
        let calendar = try makeCalendar()
        // A Thursday; the week began on Monday 9 November.
        let now = try date(calendar, 11, 12, 15)
        let counts = [
            said(try date(calendar, 11, 10), words: 800, seconds: 480),
            said(try date(calendar, 11, 11), words: 1, seconds: 2),
            said(try date(calendar, 10, 20), words: 40, seconds: 30),
        ]

        let week = summary(.week, counts: counts, now: now, calendar)
        // 800 words take 20 minutes to type, and took 8 to say.
        #expect(week.steps[1].minutesSaved == 12)
        let tuesday = HomeFormat.lineStep(week, at: 1, calendar: calendar)
        #expect(tuesday.when.contains("10"))
        #expect(tuesday.what == "800 words · 12 min saved")
        #expect(HomeFormat.lineStep(week, at: 2, calendar: calendar).what == "1 word")
        #expect(HomeFormat.lineStep(week, at: 0, calendar: calendar).what == "No words")
        // Today has time left, and the days after it haven't come.
        #expect(HomeFormat.lineStep(week, at: 3, calendar: calendar).what == "No words yet")
        #expect(HomeFormat.lineStep(week, at: 5, calendar: calendar).what == "Still to come")
        #expect(HomeFormat.lineStep(week, at: 99, calendar: calendar).what.isEmpty)

        let all = summary(.all, counts: counts, now: now, calendar)
        let thisWeek = HomeFormat.lineStep(all, at: all.steps.count - 1, calendar: calendar)
        #expect(thisWeek.when.hasPrefix("Week of "))
        #expect(thisWeek.what == "801 words · 12 min saved")

        // Someone who only writes is told of fixes instead.
        let fixes = summary(.week, actions: [proofread(try date(calendar, 11, 10), changes: 1), proofread(try date(calendar, 11, 10), changes: 0)], now: now, calendar)
        #expect(HomeFormat.lineStep(fixes, at: 1, calendar: calendar).what == "2 fixes")
        #expect(HomeFormat.lineStep(fixes, at: 0, calendar: calendar).what == "No fixes")
    }

    @Test func theYearMapHasASquareForEveryDayUpToToday() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 12, 15)
        let counts = [
            said(try date(calendar, 11, 12, 9), words: 400, seconds: 240),
            said(try date(calendar, 11, 12, 14), words: 400, seconds: 240),
            said(try date(calendar, 11, 10), words: 100),
            said(try date(calendar, 7, 6), words: 50),
            // More than a year ago: not on the map.
            said(try date(calendar, 6, 1, year: 2025), words: 999),
        ]
        let fixes = [proofread(try date(calendar, 11, 10), changes: 1), proofread(try date(calendar, 11, 10), changes: 1, applied: false)]
        let made = summary(.week, counts: counts, actions: fixes, now: now, calendar)

        #expect(made.map.count == HomeSummary.mapWeekCount)
        #expect(made.map.dropLast().allSatisfy { $0.count == 7 })
        // The current week stops at today, a Thursday.
        #expect(made.map.last?.count == 4)
        #expect(made.map.first?.first.map { calendar.isDate($0.date, inSameDayAs: try! date(calendar, 11, 10, year: 2025)) } == true)

        let today = try #require(made.map.last?.last)
        #expect(today.words == 800)
        // 800 words take 20 minutes to type, and took 8 to say.
        #expect(today.minutesSaved == 12)
        let tuesday = try #require(made.map.last?[1])
        #expect(tuesday.words == 100)
        #expect(tuesday.fixes == 1)

        #expect(made.mapTotal(.words) == 950)
        #expect(made.mapTotal(.fixes) == 1)
        #expect(made.mapLevel(of: today, .words) == 4)
        #expect(made.mapLevel(of: tuesday, .words) == 1)
        #expect(made.mapLevel(of: tuesday, .fixes) == 4)
        #expect(made.mapLevel(of: today, .fixes) == 0)
        #expect(made.countedSince.map { calendar.isDate($0, inSameDayAs: try! date(calendar, 6, 1, year: 2025)) } == true)

        let empty = summary(.week, now: now, calendar)
        #expect(empty.mapTotal(.words) == 0)
        #expect(empty.countedSince == nil)
        #expect(empty.map.joined().allSatisfy { empty.mapLevel(of: $0, .words) == 0 })
    }

    @Test func tilesFollowWhatThereIsToSay() throws {
        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 12, 15)

        let new = summary(.week, now: now, calendar)
        #expect(new.hero == .welcome)
        #expect(new.smallTiles == [.streak, .dictateTip])
        #expect(new.wideTiles == [.englishInvite])
        #expect(new.accentTile == nil)

        let dictating = summary(.week, counts: [said(now, words: 1_100, seconds: 600)], now: now, calendar)
        #expect(dictating.hero == .words)
        #expect(dictating.smallTiles == [.streak, .speed])
        #expect(dictating.wideTiles == [.timeSaved, .apps, .englishInvite])
        #expect(dictating.accentTile == .timeSaved)
        #expect(HomeFormat.heroDetail(dictating) == "1 dictation · 10 min · about 4 pages")

        // With fixes and measured proofreads there is more to say than fits, so time saved moves under the number.
        let both = summary(
            .week, counts: [said(now, words: 1_100, seconds: 600)], actions: [proofread(now, changes: 2)], now: now, calendar
        )
        #expect(both.wideTiles == [.fixes, .english, .apps])
        #expect(both.accentTile == .english)
        #expect(HomeFormat.heroDetail(both) == "1 dictation · 10 min · about 18 min saved")

        let writing = summary(.week, actions: [proofread(now, changes: 2)], now: now, calendar)
        #expect(writing.hero == .fixes)
        #expect(writing.smallTiles == [.streak, .dictateTip])
        #expect(writing.wideTiles == [.english, .apps])

        // A quiet week keeps the tiles of someone who has dictated before.
        let quiet = summary(.week, counts: [said(try date(calendar, 10, 1), words: 50)], now: now, calendar)
        #expect(quiet.hero == .words)
        #expect(quiet.words == 0)
        #expect(quiet.wideTiles == [.timeSaved, .apps, .englishInvite])
    }

    @Test func numbersAreSaidInWords() throws {
        #expect(HomeFormat.spoken(0) == "0 min")
        #expect(HomeFormat.spoken(20) == "under a minute")
        #expect(HomeFormat.spoken(2_460) == "41 min")
        #expect(HomeFormat.spoken(7_500) == "2 h 5 min")
        #expect(HomeFormat.spoken(7_200) == "2 h")
        #expect(HomeFormat.saved(minutes: 17).value == "17")
        #expect(HomeFormat.saved(minutes: 17).unit == "min")
        #expect(HomeFormat.saved(minutes: 120).value == "2")
        #expect(HomeFormat.saved(minutes: 120).unit == "h")
        #expect(HomeFormat.dictations(1) == "1 dictation")
        #expect(HomeFormat.dictations(26) == "26 dictations")
        #expect(HomeFormat.pages(1) == "about 1 page")
        #expect(HomeFormat.length(26.4) == "26 s")
        #expect(HomeFormat.length(100) == "1 min 40 s")
        #expect(HomeFormat.times(2.6).hasSuffix("×"))
        #expect(DictationCount.words(in: " two  words\nthree ") == 3)

        let calendar = try makeCalendar()
        let now = try date(calendar, 11, 12, 15)
        #expect(HomeFormat.day(try date(calendar, 11, 12, 1), now: now, calendar: calendar) == "Today")
        #expect(HomeFormat.day(try date(calendar, 11, 11, 23), now: now, calendar: calendar) == "Yesterday")
        #expect(HomeFormat.day(try date(calendar, 11, 10), now: now, calendar: calendar).contains("10"))
        #expect(HomeFormat.day(try date(calendar, 11, 10, year: 2025), now: now, calendar: calendar).contains("2025"))
    }
}

@MainActor
@Suite struct HomeModelTests {
    private func dictation(_ seconds: TimeInterval, _ text: String, app: String? = nil) -> SavedDictation {
        SavedDictation(date: Date(timeIntervalSince1970: seconds), text: text, duration: 2, model: "apple", language: nil, appName: app)
    }

    @Test func transcriptsCanBeFoundCopiedAndDeleted() {
        let harness = Harness()
        let older = dictation(1, "Older words", app: "Mail")
        let newer = dictation(2, "Newer words")
        harness.dictations.seed([older, newer])
        let home = HomeViewModel(services: harness.services)
        home.reload()
        #expect(home.transcripts.map(\.text) == ["Newer words", "Older words"])

        home.search = "mail"
        #expect(home.shownTranscripts.map(\.text) == ["Older words"])
        home.search = "words"
        #expect(home.shownTranscripts.count == 2)
        home.search = ""

        home.copy(older)
        #expect(harness.system.copied == ["Older words"])
        #expect(home.copiedID == older.id)

        home.toggleExpanded(newer.id)
        #expect(home.expanded == [newer.id])
        home.delete(id: newer.id)
        #expect(home.transcripts.map(\.text) == ["Older words"])
        // A deleted transcript isn't remembered as open.
        #expect(home.expanded.isEmpty)

        home.deleteAll()
        #expect(home.transcripts.isEmpty)
    }

    @Test func keepingFewerTranscriptsDeletesTheOldestAtOnceAndLeavesTheNumbers() {
        let harness = Harness()
        let said = (0..<14).map { dictation(TimeInterval($0), "Said \($0)") }
        harness.dictations.seed(said)
        harness.dictations.seedCounts(said.map { DictationCount(id: $0.id, date: $0.date, words: 2, duration: 2, appName: nil) })
        let home = HomeViewModel(services: harness.services)
        home.period = .all
        home.reload()

        #expect(home.transcriptsDeleted(by: .all) == 0)
        #expect(home.transcriptsDeleted(by: .last50) == 0)
        #expect(home.transcriptsDeleted(by: .last10) == 4)
        // None stops keeping more, and leaves the ones there are.
        #expect(home.transcriptsDeleted(by: .off) == 0)

        home.setHistory(.last10)
        #expect(home.transcripts.count == 10)
        #expect(home.transcripts.first?.text == "Said 13")
        #expect(home.history == .last10)
        #expect((try? harness.settings.preferences())?.dictationHistory == .last10)
        // What was dictated stays counted after its transcript is gone.
        #expect(home.summary.dictations == 14)
        #expect(home.summary.words == 28)

        home.setHistory(.off)
        #expect(home.transcripts.count == 10)
    }

    @Test func transcriptsAreShownDayByDayAndTheStretchChangesTheNumbers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Chisinau"))
        calendar.firstWeekday = 2
        func at(_ month: Int, _ day: Int, _ hour: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
        }
        let now = try at(11, 12, 15)
        let harness = Harness()
        let said = [
            SavedDictation(date: try at(11, 12, 14), text: "This afternoon", duration: 4, model: "apple", language: nil, appName: "Claude"),
            SavedDictation(date: try at(11, 12, 9), text: "This morning", duration: 4, model: "apple", language: nil, appName: "Finder"),
            SavedDictation(date: try at(11, 11, 20), text: "Last night", duration: 4, model: "apple", language: nil, appName: nil),
            SavedDictation(date: try at(11, 3, 10), text: "Last week", duration: 4, model: "apple", language: nil, appName: nil),
        ]
        harness.dictations.seed(said)
        harness.dictations.seedCounts(said.map { DictationCount(id: $0.id, date: $0.date, words: 2, duration: 4, appName: $0.appName) })
        let home = HomeViewModel(services: harness.services)
        home.reload(now: now, calendar: calendar)

        #expect(home.days.map(\.title).prefix(2) == ["Today", "Yesterday"])
        #expect(home.days.count == 3)
        #expect(home.days.first?.items.map(\.text) == ["This afternoon", "This morning"])
        home.search = "night"
        #expect(home.days.map(\.title) == ["Yesterday"])
        home.search = ""

        #expect(home.summary.period == .week)
        #expect(home.summary.dictations == 3)
        home.period = .month
        #expect(home.summary.dictations == 4)
        #expect(home.summary.steps.count == 30)
    }

    @Test func anAppIsLookedForOnceAndTheKeysAreNamedAsSettingsShowsThem() throws {
        let harness = Harness()
        let slack = URL(fileURLWithPath: "/Applications/Slack.app")
        harness.system.applicationURLs["Slack"] = slack
        var preferences = AppPreferences()
        preferences.setCombo(KeyCombo(keyCode: 35, modifiers: KeyCombo.control | KeyCombo.option), for: .proofread)
        try harness.settings.setPreferences(preferences)
        let home = HomeViewModel(services: harness.services)
        home.reload()

        #expect(home.appURL(named: "Slack") == slack)
        harness.system.applicationURLs["Slack"] = nil
        #expect(home.appURL(named: "Slack") == slack)
        #expect(home.appURL(named: "Nowhere") == nil)
        #expect(home.appURL(named: nil) == nil)
        #expect(home.proofreadKeys == "⌃⌥P")
    }

    @Test func theWindowsToolbarOpensSettingsAndNothingElse() throws {
        let harness = Harness()
        let home = HomeViewModel(services: harness.services)
        var opened = 0
        home.openSettings = { opened += 1 }
        // Made, and never shown.
        let controller = HomeWindowController(model: home)
        let toolbar = try #require(controller.window?.toolbar)

        #expect(controller.window?.title == "OmanAI")
        #expect(toolbar.items.map(\.itemIdentifier) == [.flexibleSpace, HomeWindowController.settingsItem])
        let settings = try #require(toolbar.items.last)
        #expect(settings.target === controller)
        controller.openSettings()
        #expect(opened == 1)
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

/// The column of times beside the transcripts in OmanAI's window.
@MainActor @Suite struct HomeTranscriptTimeTests {
    private func width(of text: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: HomeTranscripts.timeFontSize, weight: .regular)
        return NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    private func time(_ hour: Int, _ minute: Int, in locale: Locale) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: .gmt)
        return Date(timeIntervalSinceReferenceDate: Double(hour * 3600 + minute * 60)).formatted(style)
    }

    @Test func aTwelveHourClockGetsRoomForItsLongestTime() {
        let us = Locale(identifier: "en_US")
        let column = HomeTranscripts.timeWidth(locale: us)
        // "9:12 AM" broke onto two lines in the 44 points a 24-hour clock needs.
        #expect(column > 44)
        #expect(column >= width(of: time(12, 58, in: us)))
        #expect(column >= width(of: time(9, 12, in: us)))
    }

    @Test func aTwentyFourHourClockKeepsItsColumn() {
        let uk = Locale(identifier: "en_GB")
        #expect(HomeTranscripts.timeWidth(locale: uk) == 44)
        #expect(width(of: time(23, 58, in: uk)) < 44)
    }
}
