import Foundation
import Observation
import OmanCore

/// The Lab: what OmanAI did for the person, and their transcripts.
@MainActor
@Observable
public final class LabViewModel {
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var copiedTask: Task<Void, Never>?

    private(set) var summary = LabSummary()
    private(set) var transcripts: [SavedDictation] = []
    private(set) var history: DictationHistory = .all
    private(set) var error: String?
    private(set) var copiedID: UUID?
    var search = ""

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

    public func reload(now: Date = Date(), calendar: Calendar = .current) {
        do {
            transcripts = try services.dictations?.savedDictations() ?? []
            let actions = try services.actions?.actions(since: .distantPast) ?? []
            let usage = try services.usage?.usageEntries(since: .distantPast) ?? []
            history = ((try? services.settings.preferences()) ?? AppPreferences()).dictationHistory
            summary = LabSummary.make(
                dictations: transcripts, actions: actions, usage: usage, now: now, calendar: calendar
            )
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
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
        reload()
    }
}
