import CloudKit
import Foundation
import Observation
import OmanCore

/// Keeps the person's templates, actions and shared settings the same on each of their devices, through a zone of
/// its own in the private database of the person's iCloud. Off until the person turns it on.
///
/// CloudKit stops an app that asks for a container it isn't entitled to, so nothing here reaches CloudKit in a build
/// without one: `make` returns nil there.
@MainActor
@Observable
public final class CloudSync: CloudSyncing, CKSyncEngineDelegate {
    public private(set) var isOn: Bool
    public private(set) var status: CloudSyncStatus = .off

    /// Called after changes made elsewhere were written here, so that what shows them can read them again.
    @ObservationIgnored public var onRemoteChange: (@MainActor () -> Void)?
    /// The templates, actions and settings for the app to use in place of the database's own, so that each change
    /// is noted and sent.
    @ObservationIgnored public let stores: SyncingStores

    @ObservationIgnored private let containerIdentifier: String
    @ObservationIgnored private let styles: any StyleStore
    @ObservationIgnored private let actions: any CustomActionStore
    @ObservationIgnored private let settings: any AppSettingsStore
    @ObservationIgnored private let ledger: SyncLedger
    @ObservationIgnored private var engine: CKSyncEngine?
    /// Set when syncing is turned on, so that everything here is sent once and weighed against what iCloud has.
    @ObservationIgnored private var sendsEverything = false
    /// What went wrong in the last sync, said to the person until a sync goes through.
    @ObservationIgnored private var problem: String?
    @ObservationIgnored private var lastSync: Date?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var accountObserver: (any NSObjectProtocol)?

    /// The iCloud container this build was signed for, read from its Info.plist, or nil when it can't use iCloud.
    public nonisolated static func containerIdentifier(in bundle: Bundle = .main) -> String? {
        guard let identifier = bundle.object(forInfoDictionaryKey: "OmanICloudContainer") as? String,
              identifier.hasPrefix("iCloud.") else { return nil }
        return identifier
    }

    /// Sync in front of the database's stores, for a build signed for iCloud. Nil in a build that isn't.
    public static func make(
        styles: any StyleStore,
        actions: any CustomActionStore,
        settings: any AppSettingsStore,
        bundle: Bundle = .main
    ) -> CloudSync? {
        guard let identifier = containerIdentifier(in: bundle), let ledger = try? SyncLedger.openDefault() else {
            return nil
        }
        return CloudSync(
            containerIdentifier: identifier, styles: styles, actions: actions, settings: settings, ledger: ledger
        )
    }

    public init(
        containerIdentifier: String,
        styles: any StyleStore,
        actions: any CustomActionStore,
        settings: any AppSettingsStore,
        ledger: SyncLedger
    ) {
        let relay = ChangeRelay()
        self.containerIdentifier = containerIdentifier
        self.styles = styles
        self.actions = actions
        self.settings = settings
        self.ledger = ledger
        isOn = ledger.isOn
        stores = SyncingStores(
            styles: styles, actions: actions, settings: settings, ledger: ledger,
            changed: { recordName in
                Task { @MainActor in relay.owner?.queueLocalChange(recordName) }
            }
        )
        relay.owner = self
    }

    /// Connects when syncing is on. Called once the app has wired up `onRemoteChange`.
    public func start() {
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.accountChanged() }
        }
        if isOn { connect() }
    }

    public func setOn(_ on: Bool) {
        guard on != isOn else { return }
        isOn = on
        ledger.isOn = on
        if on {
            sendsEverything = true
            connect()
        } else {
            disconnect()
            status = .off
        }
    }

    public func syncNow() {
        guard isOn else { return }
        guard let engine else {
            connect()
            return
        }
        // After a change couldn't be sent, as when iCloud was full, everything is offered again.
        if problem != nil { queueEverything(in: engine) }
        status = .syncing
        syncTask = Task { [weak self] in
            do {
                try await engine.fetchChanges()
                try await engine.sendChanges()
                self?.finishSync(of: engine, error: nil)
            } catch {
                self?.finishSync(of: engine, error: error)
            }
        }
    }

    /// Syncs unless that was done in the last minute, as when the app comes to the front.
    public func syncIfStale() {
        guard isOn else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < 60 { return }
        syncNow()
    }

    // MARK: Connecting

    private func connect() {
        connectTask?.cancel()
        status = .syncing
        let identifier = containerIdentifier
        connectTask = Task { [weak self] in
            let container = CKContainer(identifier: identifier)
            let account: CKAccountStatus
            do {
                account = try await container.accountStatus()
            } catch {
                guard let self, isOn, !Task.isCancelled else { return }
                status = .unavailable(Self.sentence(for: error))
                return
            }
            guard let self, isOn, !Task.isCancelled else { return }
            switch account {
            case .available:
                makeEngine(database: container.privateCloudDatabase)
            case .noAccount:
                status = .noAccount
            case .restricted:
                status = .unavailable("iCloud is restricted on this device.")
            case .temporarilyUnavailable:
                status = .unavailable("iCloud needs your attention in Settings before OmanAI can sync.")
            case .couldNotDetermine:
                status = .unavailable("OmanAI couldn't reach iCloud.")
            @unknown default:
                status = .unavailable("OmanAI couldn't reach iCloud.")
            }
        }
    }

    private func makeEngine(database: CKDatabase) {
        if engine == nil {
            var configuration = CKSyncEngine.Configuration(
                database: database, stateSerialization: ledger.engineState, delegate: self
            )
            configuration.automaticallySync = true
            let engine = CKSyncEngine(configuration)
            self.engine = engine
            if sendsEverything || ledger.engineState == nil { queueEverything(in: engine) }
            sendsEverything = false
        }
        syncNow()
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            // Changes made elsewhere are fetched every few minutes, and when the app comes to the front.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard let self else { return }
                syncIfStale()
            }
        }
    }

    private func disconnect() {
        connectTask?.cancel()
        syncTask?.cancel()
        refreshTask?.cancel()
        if let engine { Task { await engine.cancelOperations() } }
        engine = nil
    }

    private func accountChanged() {
        if isOn, engine == nil { connect() }
    }

    private func finishSync(of engine: CKSyncEngine, error: (any Error)?) {
        guard engine === self.engine else { return }
        lastSync = Date()
        if let error {
            status = (error as? CKError)?.code == .notAuthenticated ? .noAccount : .unavailable(Self.sentence(for: error))
        } else {
            status = problem.map(CloudSyncStatus.unavailable) ?? .upToDate
        }
    }

    // MARK: What changed here

    /// Everything here, to be sent and weighed against what iCloud has: each template and action, the settings, and
    /// what was deleted here.
    private func queueEverything(in engine: CKSyncEngine) {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zoneID))])
        var names = ((try? styles.loadStyles()) ?? []).map { SyncRecords.recordName(.style, $0.id.uuidString) }
        names += ((try? actions.loadCustomActions()) ?? []).map { SyncRecords.recordName(.action, $0.id.uuidString) }
        names.append(SyncRecords.settingsRecordName)
        names += ledger.deletedItemNames
        for name in names { queue(name, in: engine) }
    }

    private func queueLocalChange(_ recordName: String) {
        guard isOn, let engine else { return }
        queue(recordName, in: engine)
    }

    /// A save, or a deletion for what was deleted here, in place of any change to it still waiting.
    private func queue(_ recordName: String, in engine: CKSyncEngine) {
        let id = SyncRecords.recordID(recordName)
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id), .deleteRecord(id)])
        let deleted = ledger.item(recordName)?.isDeleted == true
        engine.state.add(pendingRecordZoneChanges: [deleted ? .deleteRecord(id) : .saveRecord(id)])
    }

    // MARK: CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }
        switch event {
        case let .stateUpdate(update):
            ledger.setEngineState(update.stateSerialization)
        case let .accountChange(change):
            accountChanged(change, in: syncEngine)
        case let .fetchedDatabaseChanges(changes):
            zonesChanged(changes, in: syncEngine)
        case let .fetchedRecordZoneChanges(changes):
            var changedHere = false
            for modification in changes.modifications {
                changedHere = take(modification.record, in: syncEngine) || changedHere
            }
            for deletion in changes.deletions {
                changedHere = takeDeletion(of: deletion.recordID, in: syncEngine) || changedHere
            }
            if changedHere { onRemoteChange?() }
        case let .sentRecordZoneChanges(sent):
            recordsSent(sent, in: syncEngine)
        case let .sentDatabaseChanges(sent):
            for failure in sent.failedZoneSaves where failure.error.code == .quotaExceeded {
                problem = Self.sentence(for: failure.error)
            }
        case .willFetchChanges:
            status = .syncing
        case .willSendChanges:
            problem = nil
            status = .syncing
        case .didFetchChanges, .didSendChanges:
            lastSync = Date()
            status = problem.map(CloudSyncStatus.unavailable) ?? .upToDate
        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break
        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        var records: [CKRecord.ID: CKRecord] = [:]
        var gone: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard case let .saveRecord(id) = change else { continue }
            if let record = record(for: id) {
                records[id] = record
            } else {
                gone.append(change)
            }
        }
        if !gone.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: gone) }
        let ready = pending.filter { !gone.contains($0) }
        guard !ready.isEmpty else { return nil }
        let provided = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: ready) { id in provided[id] }
    }

    // MARK: Taking changes from iCloud

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange, in syncEngine: CKSyncEngine) {
        switch change.changeType {
        case .signIn:
            queueEverything(in: syncEngine)
        case .signOut:
            // What is here stays here. What was learnt from that account is forgotten.
            disconnect()
            ledger.forgetServer()
            status = .noAccount
        case .switchAccounts:
            disconnect()
            ledger.forgetServer()
            sendsEverything = true
            connect()
        @unknown default:
            break
        }
    }

    private func zonesChanged(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges, in syncEngine: CKSyncEngine) {
        for deletion in changes.deletions where deletion.zoneID == SyncRecords.zoneID {
            switch deletion.reason {
            case .encryptedDataReset:
                // The keys of the person's encrypted data in iCloud were reset: what is here is sent again.
                ledger.forgetSystemFields()
                queueEverything(in: syncEngine)
            case .deleted, .purged:
                // OmanAI's data was removed from iCloud. Sending it all again would undo that, so syncing stops.
                disconnect()
                ledger.forgetServer()
                isOn = false
                ledger.isOn = false
                status = .off
                return
            @unknown default:
                break
            }
        }
    }

    /// Weighs a record from iCloud against what is here: writes it here when it is newer, and queues what is here
    /// when that is. Returns whether anything here changed.
    private func take(_ record: CKRecord, in syncEngine: CKSyncEngine) -> Bool {
        let name = record.recordID.recordName
        guard let (kind, _) = SyncRecords.parse(name) else { return false }
        ledger.setSystemFields(SyncRecords.systemFields(of: record), for: name)
        if kind == .settings { return takeSettings(from: record, in: syncEngine) }

        let modified = SyncRecords.modified(record)
        switch SyncMerge.outcome(remoteModified: modified, local: ledger.item(name)) {
        case .takeRemote:
            let saved: Bool
            switch kind {
            case .style: saved = SyncRecords.style(from: record).map { (try? styles.save($0)) != nil } ?? false
            case .action: saved = SyncRecords.action(from: record).map { (try? actions.saveCustomAction($0)) != nil } ?? false
            case .settings: saved = false
            }
            guard saved else { return false }
            ledger.setItem(SyncMerge.Item(modified: modified), for: name)
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID), .deleteRecord(record.recordID)])
            return true
        case .sendLocal:
            queue(name, in: syncEngine)
            return false
        case .keep:
            return false
        }
    }

    private func takeSettings(from record: CKRecord, in syncEngine: CKSyncEngine) -> Bool {
        guard let remote = SyncRecords.settings(from: record) else { return false }
        let preferences = (try? settings.preferences()) ?? AppPreferences()
        let shared = SharedSettings(preferences)
        let local = localSettings(shared)
        let outcome = SyncMerge.merge(local: local, remote: remote)
        var dates = outcome.dates
        var changedHere = false
        if !outcome.taken.isEmpty {
            let (merged, replaced) = shared.replacing(outcome.taken)
            // A value this version can't read keeps its own date, so that it isn't taken for iCloud's.
            for name in outcome.taken.keys where !replaced.contains(name) {
                dates[name] = local.dates[name]
            }
            if merged != shared {
                var updated = preferences
                merged.apply(to: &updated)
                changedHere = (try? settings.setPreferences(updated)) != nil
            }
        }
        ledger.setSettingDates(dates)
        if outcome.sendsLocal { queue(SyncRecords.settingsRecordName, in: syncEngine) }
        return changedHere
    }

    private func takeDeletion(of id: CKRecord.ID, in syncEngine: CKSyncEngine) -> Bool {
        let name = id.recordName
        guard let (kind, itemName) = SyncRecords.parse(name), kind != .settings,
              let uuid = UUID(uuidString: itemName) else { return false }
        ledger.setSystemFields(nil, for: name)
        let hasUnsentChange = syncEngine.state.pendingRecordZoneChanges.contains(.saveRecord(id))
        guard SyncMerge.followsRemoteDeletion(hasUnsentChange: hasUnsentChange) else { return false }
        syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(id)])
        ledger.setItem(nil, for: name)
        let shortcut: ShortcutAction
        switch kind {
        case .style:
            try? styles.deleteStyle(id: uuid)
            shortcut = .style(uuid)
        case .action:
            try? actions.deleteCustomAction(id: uuid)
            shortcut = .custom(uuid)
        case .settings:
            return true
        }
        // Its shortcut belongs to this device, and goes with it, as when it is deleted here.
        if var preferences = try? settings.preferences(), preferences.combo(for: shortcut) != nil {
            preferences.setCombo(nil, for: shortcut)
            try? settings.setPreferences(preferences)
        }
        return true
    }

    private func recordsSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, in syncEngine: CKSyncEngine) {
        var changedHere = false
        for record in sent.savedRecords {
            ledger.setSystemFields(SyncRecords.systemFields(of: record), for: record.recordID.recordName)
        }
        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                // Changed elsewhere since this device last saw it: the newer version wins.
                if let server = failure.error.serverRecord {
                    changedHere = take(server, in: syncEngine) || changedHere
                }
            case .zoneNotFound:
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecords.zoneID))])
                ledger.setSystemFields(nil, for: id.recordName)
                queue(id.recordName, in: syncEngine)
            case .unknownItem:
                // Deleted in iCloud since: the change here brings it back.
                ledger.setSystemFields(nil, for: id.recordName)
                queue(id.recordName, in: syncEngine)
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
                .operationCancelled, .requestRateLimited:
                // The engine tries these again by itself.
                break
            default:
                problem = Self.sentence(for: failure.error)
            }
        }
        for id in sent.deletedRecordIDs {
            ledger.setItem(nil, for: id.recordName)
            ledger.setSystemFields(nil, for: id.recordName)
        }
        for (id, error) in sent.failedRecordDeletes where error.code == .unknownItem || error.code == .zoneNotFound {
            // Never reached iCloud, or already gone from it.
            ledger.setItem(nil, for: id.recordName)
            ledger.setSystemFields(nil, for: id.recordName)
        }
        if changedHere { onRemoteChange?() }
    }

    // MARK: Building records

    private func record(for id: CKRecord.ID) -> CKRecord? {
        let name = id.recordName
        guard let (kind, itemName) = SyncRecords.parse(name) else { return nil }
        let record = ledger.systemFields(name).flatMap(SyncRecords.record(systemFields:))
            ?? CKRecord(recordType: kind.rawValue, recordID: id)
        let modified = ledger.item(name)?.modified ?? SyncMerge.unknownDate
        switch kind {
        case .style:
            guard let uuid = UUID(uuidString: itemName),
                  let style = (try? styles.loadStyles())?.first(where: { $0.id == uuid }) else { return nil }
            SyncRecords.write(style, modified: modified, into: record)
        case .action:
            guard let uuid = UUID(uuidString: itemName),
                  let action = (try? actions.loadCustomActions())?.first(where: { $0.id == uuid }) else { return nil }
            SyncRecords.write(action, modified: modified, into: record)
        case .settings:
            let shared = SharedSettings((try? settings.preferences()) ?? AppPreferences())
            SyncRecords.write(localSettings(shared), into: record)
        }
        return record
    }

    /// This device's shared settings, with a date for each field.
    private func localSettings(_ shared: SharedSettings) -> SyncMerge.Settings {
        let fields = shared.fields()
        let defaults = SharedSettings(AppPreferences()).fields()
        return SyncMerge.Settings(
            fields: fields,
            dates: SyncMerge.filledDates(ledger.settingDates, fields: fields, defaults: defaults)
        )
    }

    nonisolated static func sentence(for error: any Error) -> String {
        guard let error = error as? CKError else { return "iCloud couldn't sync: \(error.localizedDescription)" }
        switch error.code {
        case .networkUnavailable, .networkFailure:
            return "You're offline. OmanAI syncs when you're back online."
        case .quotaExceeded:
            return "Your iCloud storage is full, so changes stay on this device for now."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is busy. OmanAI tries again shortly."
        case .limitExceeded:
            return "A template is too long for iCloud, so it stays on this device."
        default:
            return "iCloud couldn't sync: \(error.localizedDescription)"
        }
    }
}

/// Passes changes noted by the stores on to the sync, which is made after them.
@MainActor
private final class ChangeRelay {
    weak var owner: CloudSync?
}
