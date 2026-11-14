import CloudKit
import Foundation
import os

/// What this device knows about syncing, kept in a file beside the database: whether syncing is on, when each
/// template, action and setting last changed here, the parts of each record iCloud needs to see a save as a change
/// to it, and the sync engine's own state. Read and written from any thread.
public final class SyncLedger: Sendable {
    struct Contents: Codable, Sendable {
        var isOn = false
        var items: [String: SyncMerge.Item] = [:]
        var settingDates: [String: Date] = [:]
        var systemFields: [String: Data] = [:]
        var engineState: CKSyncEngine.State.Serialization?
    }

    private let fileURL: URL?
    private let contents: OSAllocatedUnfairLock<Contents>

    /// Without a file, as in tests, nothing is kept after the ledger goes.
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        let saved = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Contents.self, from: $0) }
        contents = OSAllocatedUnfairLock(initialState: saved ?? Contents())
    }

    /// The ledger beside the database, in OmanAI's folder in Application Support.
    public static func openDefault() throws -> SyncLedger {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("oman", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return SyncLedger(fileURL: folder.appendingPathComponent("sync.json"))
    }

    public var isOn: Bool {
        get { contents.withLock { $0.isOn } }
        set { change { $0.isOn = newValue } }
    }

    public func item(_ name: String) -> SyncMerge.Item? {
        contents.withLock { $0.items[name] }
    }

    public func setItem(_ item: SyncMerge.Item?, for name: String) {
        change { $0.items[name] = item }
    }

    /// The templates and actions deleted here and not yet in iCloud.
    public var deletedItemNames: [String] {
        contents.withLock { contents in contents.items.filter(\.value.isDeleted).map(\.key) }
    }

    public var settingDates: [String: Date] {
        contents.withLock { $0.settingDates }
    }

    public func setSettingDates(_ dates: [String: Date]) {
        change { $0.settingDates.merge(dates) { _, new in new } }
    }

    public func systemFields(_ name: String) -> Data? {
        contents.withLock { $0.systemFields[name] }
    }

    public func setSystemFields(_ data: Data?, for name: String) {
        change { $0.systemFields[name] = data }
    }

    public var engineState: CKSyncEngine.State.Serialization? {
        contents.withLock { $0.engineState }
    }

    public func setEngineState(_ state: CKSyncEngine.State.Serialization?) {
        change { $0.engineState = state }
    }

    /// Forgets everything learnt from iCloud, as when another account signs in, and keeps what changed here and
    /// when, so that it can all be sent again.
    public func forgetServer() {
        change { contents in
            contents.systemFields = [:]
            contents.engineState = nil
        }
    }

    /// Forgets the parts of each record iCloud needs to see a save as a change, as when the keys of the person's
    /// encrypted data were reset, so that each record is made anew.
    public func forgetSystemFields() {
        change { $0.systemFields = [:] }
    }

    // Written while the lock is held, so that two changes can't reach the file in the wrong order.
    private func change(_ body: (inout Contents) -> Void) {
        contents.withLockUnchecked { contents in
            body(&contents)
            guard let fileURL, let data = try? JSONEncoder().encode(contents) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
