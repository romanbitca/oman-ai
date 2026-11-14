import CloudKit
import Foundation
import OmanCore
import Testing

@testable import OmanSync

// MARK: Fakes

final class MemoryStores: StyleStore, CustomActionStore, AppSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var styles: [WritingStyle] = []
    private var actions: [CustomAction] = []
    private var stored = AppPreferences()
    private var model: WritingModel = .default
    private var lastByApp: [String: StyleChoice] = [:]

    func loadStyles() throws -> [WritingStyle] { lock.withLock { styles } }

    func save(_ style: WritingStyle) throws {
        lock.withLock {
            if let index = styles.firstIndex(where: { $0.id == style.id }) {
                styles[index] = style
            } else {
                styles.append(style)
            }
        }
    }

    func deleteStyle(id: UUID) throws { lock.withLock { styles.removeAll { $0.id == id } } }
    func lastStyleChoice(forApp key: String) throws -> StyleChoice? { lock.withLock { lastByApp[key] } }
    func setLastStyleChoice(_ choice: StyleChoice?, forApp key: String) throws { lock.withLock { lastByApp[key] = choice } }

    func loadCustomActions() throws -> [CustomAction] { lock.withLock { actions } }

    func saveCustomAction(_ action: CustomAction) throws {
        lock.withLock {
            if let index = actions.firstIndex(where: { $0.id == action.id }) {
                actions[index] = action
            } else {
                actions.append(action)
            }
        }
    }

    func deleteCustomAction(id: UUID) throws { lock.withLock { actions.removeAll { $0.id == id } } }
    func selectedModel() throws -> WritingModel { lock.withLock { model } }
    func setSelectedModel(_ model: WritingModel) throws { lock.withLock { self.model = model } }
    func preferences() throws -> AppPreferences { lock.withLock { stored } }
    func setPreferences(_ preferences: AppPreferences) throws { lock.withLock { stored = preferences } }
}

final class ChangeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    var all: [String] { lock.withLock { names } }
    func add(_ name: String) { lock.withLock { names.append(name) } }
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_800_000_000 + seconds)
}

private func json(_ text: String) -> Data {
    Data(text.utf8)
}

// MARK: Merging

@Suite struct ItemMergeTests {
    @Test func aVersionWithNothingNotedHereIsTaken() {
        #expect(SyncMerge.outcome(remoteModified: date(0), local: nil) == .takeRemote)
    }

    @Test func theNewerChangeWins() {
        let local = SyncMerge.Item(modified: date(10))
        #expect(SyncMerge.outcome(remoteModified: date(20), local: local) == .takeRemote)
        #expect(SyncMerge.outcome(remoteModified: date(5), local: local) == .sendLocal)
        #expect(SyncMerge.outcome(remoteModified: date(10), local: local) == .keep)
    }

    @Test func aDeletionHereWinsOverAnOlderVersionAndLosesToANewerOne() {
        let deleted = SyncMerge.Item(modified: date(10), isDeleted: true)
        #expect(SyncMerge.outcome(remoteModified: date(5), local: deleted) == .sendLocal)
        #expect(SyncMerge.outcome(remoteModified: date(10), local: deleted) == .sendLocal)
        #expect(SyncMerge.outcome(remoteModified: date(20), local: deleted) == .takeRemote)
    }

    @Test func aDeletionElsewhereIsFollowedUnlessAChangeHereWaits() {
        #expect(SyncMerge.followsRemoteDeletion(hasUnsentChange: false))
        #expect(!SyncMerge.followsRemoteDeletion(hasUnsentChange: true))
    }
}

@Suite struct SettingsMergeTests {
    @Test func eachFieldIsTakenFromTheSideThatChangedItLast() {
        let local = SyncMerge.Settings(
            fields: ["quality": json("\"fast\""), "outputLanguage": json("\"German\"")],
            dates: ["quality": date(10), "outputLanguage": date(30)]
        )
        let remote = SyncMerge.Settings(
            fields: ["quality": json("\"best\""), "outputLanguage": json("\"French\"")],
            dates: ["quality": date(20), "outputLanguage": date(25)]
        )
        let outcome = SyncMerge.merge(local: local, remote: remote)
        #expect(outcome.taken == ["quality": json("\"best\"")])
        #expect(outcome.dates == ["quality": date(20), "outputLanguage": date(30)])
        #expect(outcome.sendsLocal)
    }

    @Test func atTheSameDateICloudsValueWins() {
        let local = SyncMerge.Settings(fields: ["quality": json("\"fast\"")], dates: ["quality": date(10)])
        let remote = SyncMerge.Settings(fields: ["quality": json("\"best\"")], dates: ["quality": date(10)])
        let outcome = SyncMerge.merge(local: local, remote: remote)
        #expect(outcome.taken == ["quality": json("\"best\"")])
        #expect(!outcome.sendsLocal)
    }

    @Test func theSameSettingsComingBackChangeNothing() {
        let settings = SyncMerge.Settings(fields: ["quality": json("\"fast\"")], dates: ["quality": date(10)])
        let outcome = SyncMerge.merge(local: settings, remote: settings)
        #expect(outcome.taken.isEmpty)
        #expect(!outcome.sendsLocal)
    }

    @Test func aFieldICloudDoesntHaveIsSent() {
        let local = SyncMerge.Settings(
            fields: ["quality": json("\"fast\""), "removesFillerWords": json("true")],
            dates: ["quality": date(10), "removesFillerWords": date(10)]
        )
        let remote = SyncMerge.Settings(fields: ["quality": json("\"fast\"")], dates: ["quality": date(10)])
        let outcome = SyncMerge.merge(local: local, remote: remote)
        #expect(outcome.taken.isEmpty)
        #expect(outcome.sendsLocal)
    }

    /// The Mac's settings were changed before syncing existed, and the iPhone's are new: whichever turns syncing on
    /// first, both end with the Mac's.
    @Test func settingsChangedBeforeSyncingWinOverDefaults() {
        let defaults = SharedSettings(AppPreferences()).fields()
        var custom = AppPreferences()
        custom.customInstructions = "Write in British English."
        let macFields = SharedSettings(custom).fields()
        let mac = SyncMerge.Settings(fields: macFields, dates: SyncMerge.filledDates([:], fields: macFields, defaults: defaults))
        let phone = SyncMerge.Settings(fields: defaults, dates: SyncMerge.filledDates([:], fields: defaults, defaults: defaults))

        let phoneSecond = SyncMerge.merge(local: phone, remote: mac)
        #expect(phoneSecond.taken == ["customInstructions": macFields["customInstructions"]])
        #expect(!phoneSecond.sendsLocal)

        let macSecond = SyncMerge.merge(local: mac, remote: phone)
        #expect(macSecond.taken.isEmpty)
        #expect(macSecond.sendsLocal)
    }

    @Test func aFieldWithoutADateIsOldestAtItsDefaultAndJustNewerWhenChanged() {
        let defaults = ["quality": json("\"fast\""), "outputLanguage": json("\"\"")]
        let fields = ["quality": json("\"fast\""), "outputLanguage": json("\"German\"")]
        let dates = SyncMerge.filledDates(["quality": date(5)], fields: fields, defaults: defaults)
        #expect(dates == ["quality": date(5), "outputLanguage": SyncMerge.unnotedChangeDate])
        #expect(SyncMerge.filledDates([:], fields: defaults, defaults: defaults).values.allSatisfy {
            $0 == SyncMerge.unknownDate
        })
    }
}

// MARK: Settings as fields

@Suite struct SharedSettingsTests {
    @Test func everyFieldIsListedAndANoneIsNull() {
        let fields = SharedSettings(AppPreferences()).fields()
        #expect(Set(fields.keys) == Set(SharedSettings.fieldNames))
        #expect(fields["defaultStyleID"] == json("null"))
        #expect(fields["removesFillerWords"] == json("true"))
    }

    @Test func fieldsFromAnotherDeviceArePutIn() {
        let here = SharedSettings(AppPreferences())
        var elsewhere = AppPreferences()
        let style = UUID()
        elsewhere.defaultStyleID = style
        elsewhere.dictationWords = ["Oman", "Roman"]
        elsewhere.quality = .best
        let fields = SharedSettings(elsewhere).fields()

        let (settings, replaced) = here.replacing([
            "defaultStyleID": fields["defaultStyleID"] ?? Data(),
            "dictationWords": fields["dictationWords"] ?? Data(),
        ])
        #expect(settings.defaultStyleID == style)
        #expect(settings.dictationWords == ["Oman", "Roman"])
        #expect(settings.quality == here.quality)
        #expect(replaced == ["defaultStyleID", "dictationWords"])

        let (cleared, _) = settings.replacing(["defaultStyleID": json("null")])
        #expect(cleared.defaultStyleID == nil)
    }

    @Test func aValueThisVersionCantReadKeepsTheOneHere() {
        let here = SharedSettings(AppPreferences())
        let (settings, replaced) = here.replacing([
            "quality": json("\"a choice from a later version\""),
            "outputLanguage": json("\"Romanian\""),
            "aFieldFromALaterVersion": json("1"),
        ])
        #expect(settings.quality == here.quality)
        #expect(settings.outputLanguage == "Romanian")
        #expect(replaced == ["outputLanguage"])
    }

    @Test func onlyTheSharedSettingsAreApplied() {
        var elsewhere = AppPreferences()
        elsewhere.customInstructions = "Short sentences."
        elsewhere.appearance = .dark
        var here = AppPreferences()
        here.keepsPanelOpen = true
        SharedSettings(elsewhere).apply(to: &here)
        #expect(here.customInstructions == "Short sentences.")
        #expect(here.appearance == AppPreferences().appearance)
        #expect(here.keepsPanelOpen)
    }
}

// MARK: Records

@Suite struct SyncRecordTests {
    @Test func aRecordNameSaysItsKindAndItem() {
        let id = UUID()
        let name = SyncRecords.recordName(.style, id.uuidString)
        #expect(SyncRecords.parse(name)?.kind == .style)
        #expect(SyncRecords.parse(name)?.name == id.uuidString)
        #expect(SyncRecords.parse(SyncRecords.settingsRecordName)?.kind == .settings)
        #expect(SyncRecords.parse("Note.1") == nil)
        #expect(SyncRecords.parse("Style.") == nil)
        #expect(SyncRecords.parse("Style") == nil)
        #expect(SyncRecords.recordID(name).zoneID.zoneName == "OmanAI")
    }

    @Test func aTemplateGoesThroughARecordWhole() {
        let style = WritingStyle(
            name: "Work",
            note: "Plain and kind.",
            samples: [StyleSample(text: "Thanks, see you Monday."), StyleSample(text: "Sounds good.")]
        )
        let name = SyncRecords.recordName(.style, style.id.uuidString)
        let record = CKRecord(recordType: "Style", recordID: SyncRecords.recordID(name))
        SyncRecords.write(style, modified: date(42), into: record)
        #expect(SyncRecords.style(from: record) == style)
        #expect(SyncRecords.modified(record) == date(42))
        #expect(record["name"] == nil, "The template's words are only in the encrypted fields")
    }

    @Test func anActionGoesThroughARecordWhole() {
        let action = CustomAction(name: "Summarise", instruction: "Three bullet points.", output: .read)
        let record = CKRecord(
            recordType: "Action",
            recordID: SyncRecords.recordID(SyncRecords.recordName(.action, action.id.uuidString))
        )
        SyncRecords.write(action, modified: date(1), into: record)
        #expect(SyncRecords.action(from: record) == action)
        #expect(SyncRecords.style(from: record) == nil)
    }

    @Test func settingsGoThroughARecordWithTheirDates() {
        var preferences = AppPreferences()
        preferences.outputLanguage = "German"
        preferences.defaultStyleID = UUID()
        let fields = SharedSettings(preferences).fields()
        let dates = Dictionary(uniqueKeysWithValues: fields.keys.map { ($0, date(7)) })
        let record = CKRecord(recordType: "Settings", recordID: SyncRecords.recordID(SyncRecords.settingsRecordName))
        SyncRecords.write(SyncMerge.Settings(fields: fields, dates: dates), into: record)

        let read = SyncRecords.settings(from: record)
        #expect(read?.fields == fields)
        #expect(read?.dates == dates)
        #expect(SyncRecords.modified(record) == date(7))
    }

    @Test func aRecordIsMadeAgainFromItsSystemFields() throws {
        let id = SyncRecords.recordID(SyncRecords.recordName(.action, UUID().uuidString))
        let record = CKRecord(recordType: "Action", recordID: id)
        let made = try #require(SyncRecords.record(systemFields: SyncRecords.systemFields(of: record)))
        #expect(made.recordID == id)
        #expect(made.recordType == "Action")
    }
}

// MARK: The ledger

@Suite struct SyncLedgerTests {
    @Test func whatIsNotedIsReadBackFromTheFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sync.json")

        let ledger = SyncLedger(fileURL: file)
        ledger.isOn = true
        ledger.setItem(SyncMerge.Item(modified: date(3)), for: "Style.a")
        ledger.setItem(SyncMerge.Item(modified: date(4), isDeleted: true), for: "Action.b")
        ledger.setSettingDates(["quality": date(5)])
        ledger.setSystemFields(Data([1, 2, 3]), for: "Style.a")

        let reopened = SyncLedger(fileURL: file)
        #expect(reopened.isOn)
        #expect(reopened.item("Style.a") == SyncMerge.Item(modified: date(3)))
        #expect(reopened.deletedItemNames == ["Action.b"])
        #expect(reopened.settingDates == ["quality": date(5)])
        #expect(reopened.systemFields("Style.a") == Data([1, 2, 3]))
    }

    @Test func forgettingTheServerKeepsWhatChangedHere() {
        let ledger = SyncLedger(fileURL: nil)
        ledger.setItem(SyncMerge.Item(modified: date(3)), for: "Style.a")
        ledger.setSettingDates(["quality": date(5)])
        ledger.setSystemFields(Data([1]), for: "Style.a")
        ledger.forgetServer()
        #expect(ledger.systemFields("Style.a") == nil)
        #expect(ledger.engineState == nil)
        #expect(ledger.item("Style.a") != nil)
        #expect(ledger.settingDates == ["quality": date(5)])
    }

    @Test func settingDatesAreAddedToWhatIsThere() {
        let ledger = SyncLedger(fileURL: nil)
        ledger.setSettingDates(["quality": date(1), "outputLanguage": date(1)])
        ledger.setSettingDates(["quality": date(2)])
        #expect(ledger.settingDates == ["quality": date(2), "outputLanguage": date(1)])
    }
}

// MARK: The stores in front of the database

@Suite struct SyncingStoresTests {
    private func make(at seconds: TimeInterval = 100) -> (SyncingStores, MemoryStores, SyncLedger, ChangeLog) {
        let base = MemoryStores()
        let ledger = SyncLedger(fileURL: nil)
        let log = ChangeLog()
        let stores = SyncingStores(
            styles: base, actions: base, settings: base, ledger: ledger,
            now: { date(seconds) },
            changed: { log.add($0) }
        )
        return (stores, base, ledger, log)
    }

    @Test func aChangedTemplateIsNotedWithItsDate() throws {
        let (stores, base, ledger, log) = make()
        let style = WritingStyle(name: "Work")
        try stores.save(style)
        let name = SyncRecords.recordName(.style, style.id.uuidString)
        #expect(try base.loadStyles() == [style])
        #expect(ledger.item(name) == SyncMerge.Item(modified: date(100)))
        #expect(log.all == [name])

        try stores.save(style)
        #expect(log.all == [name], "Saving it unchanged sends nothing")
    }

    @Test func aDeletedActionIsNotedAsDeleted() throws {
        let (stores, base, ledger, log) = make()
        let action = CustomAction(name: "Shorten")
        try base.saveCustomAction(action)
        try stores.deleteCustomAction(id: action.id)
        let name = SyncRecords.recordName(.action, action.id.uuidString)
        #expect(try base.loadCustomActions().isEmpty)
        #expect(ledger.item(name) == SyncMerge.Item(modified: date(100), isDeleted: true))
        #expect(ledger.deletedItemNames == [name])
        #expect(log.all == [name])
    }

    @Test func onlyASharedSettingIsNoted() throws {
        let (stores, _, ledger, log) = make()
        var preferences = try stores.preferences()
        preferences.appearance = .dark
        preferences.keepsPanelOpen = true
        try stores.setPreferences(preferences)
        #expect(log.all.isEmpty)
        #expect(ledger.settingDates.isEmpty)

        preferences.customInstructions = "Short sentences."
        try stores.setPreferences(preferences)
        #expect(log.all == [SyncRecords.settingsRecordName])
        #expect(ledger.settingDates == ["customInstructions": date(100)])
        #expect(try stores.preferences().customInstructions == "Short sentences.")
    }

    @Test func whatBelongsToThisDeviceGoesStraightThrough() throws {
        let (stores, base, _, log) = make()
        try stores.setLastStyleChoice(.asWritten, forApp: "com.apple.mail")
        try stores.setSelectedModel(.default)
        #expect(try base.lastStyleChoice(forApp: "com.apple.mail") == .asWritten)
        #expect(log.all.isEmpty)
    }
}

// MARK: Builds without iCloud

@MainActor @Suite struct CloudSyncAvailabilityTests {
    @Test func aBuildWithoutAContainerNeverReachesCloudKit() {
        #expect(CloudSync.containerIdentifier(in: .main) == nil)
        let stores = MemoryStores()
        #expect(CloudSync.make(styles: stores, actions: stores, settings: stores, bundle: .main) == nil)
    }
}
