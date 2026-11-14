import Foundation
import OmanCore

/// Stands in front of the database's templates, actions and settings. Each change is noted in the ledger with its
/// date, whether syncing is on or not, so that it can be weighed against changes made elsewhere when it is sent.
/// What belongs to this device only, such as the template last chosen in each app, goes straight through.
public final class SyncingStores: StyleStore, CustomActionStore, AppSettingsStore, Sendable {
    private let styles: any StyleStore
    private let actions: any CustomActionStore
    private let settings: any AppSettingsStore
    private let ledger: SyncLedger
    private let now: @Sendable () -> Date
    /// Told the name of each record that changed here.
    private let changed: @Sendable (_ recordName: String) -> Void

    public init(
        styles: any StyleStore,
        actions: any CustomActionStore,
        settings: any AppSettingsStore,
        ledger: SyncLedger,
        now: @escaping @Sendable () -> Date = { Date() },
        changed: @escaping @Sendable (_ recordName: String) -> Void
    ) {
        self.styles = styles
        self.actions = actions
        self.settings = settings
        self.ledger = ledger
        self.now = now
        self.changed = changed
    }

    // MARK: Templates

    public func loadStyles() throws -> [WritingStyle] {
        try styles.loadStyles()
    }

    public func save(_ style: WritingStyle) throws {
        let before = try? styles.loadStyles().first { $0.id == style.id }
        try styles.save(style)
        if before != style { note(SyncRecords.recordName(.style, style.id.uuidString), deleted: false) }
    }

    public func deleteStyle(id: UUID) throws {
        try styles.deleteStyle(id: id)
        note(SyncRecords.recordName(.style, id.uuidString), deleted: true)
    }

    public func lastStyleChoice(forApp key: String) throws -> StyleChoice? {
        try styles.lastStyleChoice(forApp: key)
    }

    public func setLastStyleChoice(_ choice: StyleChoice?, forApp key: String) throws {
        try styles.setLastStyleChoice(choice, forApp: key)
    }

    // MARK: Actions

    public func loadCustomActions() throws -> [CustomAction] {
        try actions.loadCustomActions()
    }

    public func saveCustomAction(_ action: CustomAction) throws {
        let before = try? actions.loadCustomActions().first { $0.id == action.id }
        try actions.saveCustomAction(action)
        if before != action { note(SyncRecords.recordName(.action, action.id.uuidString), deleted: false) }
    }

    public func deleteCustomAction(id: UUID) throws {
        try actions.deleteCustomAction(id: id)
        note(SyncRecords.recordName(.action, id.uuidString), deleted: true)
    }

    // MARK: Settings

    public func selectedModel() throws -> WritingModel {
        try settings.selectedModel()
    }

    public func setSelectedModel(_ model: WritingModel) throws {
        try settings.setSelectedModel(model)
    }

    public func preferences() throws -> AppPreferences {
        try settings.preferences()
    }

    public func setPreferences(_ preferences: AppPreferences) throws {
        let before = (try? settings.preferences()).map { SharedSettings($0).fields() } ?? [:]
        try settings.setPreferences(preferences)
        let after = SharedSettings(preferences).fields()
        let date = now()
        var dates: [String: Date] = [:]
        for (name, value) in after where before[name] != value {
            dates[name] = date
        }
        guard !dates.isEmpty else { return }
        ledger.setSettingDates(dates)
        changed(SyncRecords.settingsRecordName)
    }

    private func note(_ recordName: String, deleted: Bool) {
        ledger.setItem(SyncMerge.Item(modified: now(), isDeleted: deleted), for: recordName)
        changed(recordName)
    }
}
