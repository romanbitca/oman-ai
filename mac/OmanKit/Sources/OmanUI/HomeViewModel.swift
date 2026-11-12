import Foundation
import Observation
import OmanCore

/// OmanAI's own window: what it did for the person in a stretch of time, and their transcripts.
@MainActor
@Observable
public final class HomeViewModel {
    /// The transcripts of one day, under its heading.
    struct Day: Identifiable, Equatable {
        let title: String
        let items: [SavedDictation]
        var id: String { title }
    }

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var copiedTask: Task<Void, Never>?
    @ObservationIgnored private var counts: [DictationCount] = []
    @ObservationIgnored private var actions: [WritingAction] = []
    @ObservationIgnored private var appURLs: [String: URL?] = [:]
    @ObservationIgnored private var now = Date()
    @ObservationIgnored private var calendar = Calendar.current
    /// Opens Settings. The app shell, which owns that window, sets it.
    @ObservationIgnored public var openSettings: @MainActor () -> Void = {}

    private(set) var summary = HomeSummary()
    private(set) var transcripts: [SavedDictation] = []
    private(set) var history: DictationHistory = .all
    private(set) var error: String?
    private(set) var copiedID: UUID?
    /// The keys that proofread a selection and that dictate, as Settings shows them, for the tiles that invite.
    private(set) var proofreadKeys: String?
    private(set) var dictationKeys: String?
    /// Transcripts shown in full.
    var expanded: Set<UUID> = []
    var search = ""
    var period = HomeSummary.Period.week {
        didSet { if period != oldValue { summarize() } }
    }

    public init(services: AppServices) {
        self.services = services
    }

    /// The transcripts that match the search, in their words or their app's name.
    var shownTranscripts: [SavedDictation] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return transcripts }
        return transcripts.filter {
            $0.text.localizedCaseInsensitiveContains(query) || ($0.appName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// The shown transcripts day by day, newest first.
    var days: [Day] {
        var days: [Day] = []
        var title = ""
        var items: [SavedDictation] = []
        for dictation in shownTranscripts {
            let heading = HomeFormat.day(dictation.date, now: now, calendar: calendar)
            if heading != title, !items.isEmpty {
                days.append(Day(title: title, items: items))
                items = []
            }
            title = heading
            items.append(dictation)
        }
        if !items.isEmpty { days.append(Day(title: title, items: items)) }
        return days
    }

    public func reload(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        do {
            transcripts = try services.dictations?.savedDictations() ?? []
            counts = try services.dictations?.dictationCounts(since: .distantPast) ?? []
            actions = try services.actions?.actions(since: .distantPast) ?? []
            let preferences = (try? services.settings.preferences()) ?? AppPreferences()
            history = preferences.dictationHistory
            proofreadKeys = preferences.combo(for: .proofread)?.displayString
            dictationKeys = (preferences.dictationHoldKey ?? preferences.dictationLongKey)?.displayName
                ?? (preferences.combo(for: .dictateHold) ?? preferences.combo(for: .dictateLong))?.displayString
            expanded.formIntersection(transcripts.map(\.id))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        summarize()
    }

    private func summarize() {
        summary = HomeSummary.make(counts: counts, actions: actions, period: period, now: now, calendar: calendar)
    }

    /// Where the app a dictation went into is, for its icon. Looked up once for each name.
    func appURL(named name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        if let known = appURLs[name] { return known }
        let url = services.system.applicationURL(named: name)
        appURLs[name] = url
        return url
    }

    func copy(_ dictation: SavedDictation) {
        services.system.copyToClipboard(dictation.text)
        copiedID = dictation.id
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.copiedID = nil
        }
    }

    func toggleExpanded(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    func delete(id: UUID) {
        change { try services.dictations?.deleteDictation(id: id) }
    }

    func deleteAll() {
        change { try services.dictations?.deleteAllDictations() }
    }

    /// How many transcripts the choice would delete now. None keeps the old ones and only stops keeping more.
    func transcriptsDeleted(by history: DictationHistory) -> Int {
        guard history != .off, let limit = history.limit else { return 0 }
        return max(transcripts.count - limit, 0)
    }

    func setHistory(_ history: DictationHistory) {
        do {
            var preferences = try services.settings.preferences()
            preferences.dictationHistory = history
            try services.settings.setPreferences(preferences)
            self.history = history
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard transcriptsDeleted(by: history) > 0, let limit = history.limit else { return }
        change { try services.dictations?.trimDictations(keepingNewest: limit) }
    }

    private func change(_ body: () throws -> Void) {
        do {
            try body()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        reload(now: now, calendar: calendar)
    }
}
