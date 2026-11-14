import Foundation

/// Decides between what this device has and what comes from iCloud. Each template and action is taken whole, and the
/// newer change wins. Settings are weighed a field at a time, so a change to one setting on the iPhone doesn't undo a
/// change to another on the Mac.
public enum SyncMerge {
    /// The date of a change made before anything was noted, so that any change noted since wins over it.
    public static let unknownDate = Date(timeIntervalSince1970: 0)
    /// The date given to a setting changed from its default before anything was noted: newer than a default nobody
    /// chose, older than any change noted since.
    public static let unnotedChangeDate = Date(timeIntervalSince1970: 1)

    /// What this device knows of a template or action.
    public struct Item: Codable, Equatable, Sendable {
        /// When it last changed here, or when the version taken from iCloud was made.
        public var modified: Date
        /// Deleted here, and not yet deleted in iCloud.
        public var isDeleted: Bool

        public init(modified: Date, isDeleted: Bool = false) {
            self.modified = modified
            self.isDeleted = isDeleted
        }
    }

    public enum ItemOutcome: Equatable, Sendable {
        /// The version from iCloud replaces this device's.
        case takeRemote
        /// This device's version, or its deletion, is newer, and is to be sent.
        case sendLocal
        /// Both are the same version.
        case keep
    }

    /// Weighs a version of a template or action fetched from iCloud against this device's. Without a note of it
    /// here, the version from iCloud is taken.
    public static func outcome(remoteModified: Date, local: Item?) -> ItemOutcome {
        guard let local else { return .takeRemote }
        if local.isDeleted { return remoteModified > local.modified ? .takeRemote : .sendLocal }
        if remoteModified > local.modified { return .takeRemote }
        return remoteModified < local.modified ? .sendLocal : .keep
    }

    /// A deletion in iCloud is followed, unless this device changed the template or action since and has yet to
    /// send it: then the change brings it back.
    public static func followsRemoteDeletion(hasUnsentChange: Bool) -> Bool {
        !hasUnsentChange
    }

    /// One side of the settings: each field's JSON, and when each was changed.
    public struct Settings: Equatable, Sendable {
        public var fields: [String: Data]
        public var dates: [String: Date]

        public init(fields: [String: Data], dates: [String: Date]) {
            self.fields = fields
            self.dates = dates
        }
    }

    public struct SettingsOutcome: Equatable, Sendable {
        /// The fields to take from iCloud, with their values.
        public var taken: [String: Data]
        /// When each field changed, after the merge.
        public var dates: [String: Date]
        /// Whether this device has fields newer than iCloud's, so that the merged settings are to be sent.
        public var sendsLocal: Bool
    }

    /// Takes each field from the side that changed it last. At the same date, iCloud's wins, so that the device that
    /// syncs second takes on what the first one sent.
    public static func merge(local: Settings, remote: Settings) -> SettingsOutcome {
        var taken: [String: Data] = [:]
        var dates = local.dates
        var sendsLocal = false
        for name in Set(local.fields.keys).union(remote.fields.keys) {
            let localDate = local.dates[name] ?? unknownDate
            guard let remoteValue = remote.fields[name], let remoteDate = remote.dates[name] else {
                // iCloud doesn't have this field yet, as when an older version sent the settings.
                if local.fields[name] != nil { sendsLocal = true }
                continue
            }
            if remoteDate >= localDate {
                if local.fields[name] != remoteValue { taken[name] = remoteValue }
                dates[name] = remoteDate
            } else {
                sendsLocal = true
            }
        }
        return SettingsOutcome(taken: taken, dates: dates, sendsLocal: sendsLocal)
    }

    /// The dates of this device's settings, with a date filled in for each field that has none: a field still at
    /// its default is the oldest of all, and one changed from it before anything was noted is just newer.
    public static func filledDates(_ dates: [String: Date], fields: [String: Data], defaults: [String: Data])
        -> [String: Date]
    {
        var result = dates
        for (name, value) in fields where result[name] == nil {
            result[name] = value == defaults[name] ? unknownDate : unnotedChangeDate
        }
        return result
    }
}
