import CloudKit
import Foundation
import OmanCore

/// What OmanAI keeps in the person's own iCloud, in a zone of its own: a record for each template and each action,
/// and one for the settings that follow the person. What they wrote is in encrypted fields, which iCloud encrypts on
/// the device with keys only the person's devices hold; only the dates of changes are readable to iCloud.
public enum SyncRecords {
    public static let zoneName = "OmanAI"
    /// The name of the one settings record.
    public static let settingsName = "shared"

    public enum Kind: String, Sendable, CaseIterable {
        case style = "Style"
        case action = "Action"
        case settings = "Settings"
    }

    public static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// The record's name: its kind, a dot, and the template's or action's identifier.
    public static func recordName(_ kind: Kind, _ name: String) -> String {
        "\(kind.rawValue).\(name)"
    }

    public static func recordID(_ recordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    public static var settingsRecordName: String { recordName(.settings, settingsName) }

    /// The kind and name a record's name stands for, or nil for one OmanAI didn't make.
    public static func parse(_ recordName: String) -> (kind: Kind, name: String)? {
        let parts = recordName.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, let kind = Kind(rawValue: String(parts[0])), !parts[1].isEmpty else { return nil }
        return (kind, String(parts[1]))
    }

    /// When the record's content last changed, as the device that changed it said.
    public static func modified(_ record: CKRecord) -> Date {
        record["modified"] as? Date ?? SyncMerge.unknownDate
    }

    // MARK: The parts iCloud needs to see a save as a change to a record it has

    public static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    /// An empty record with the given system fields, to fill in and save.
    public static func record(systemFields data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: Templates

    private struct Sample: Codable {
        var id: UUID
        var text: String
    }

    public static func write(_ style: WritingStyle, modified: Date, into record: CKRecord) {
        record.encryptedValues["name"] = style.name
        record.encryptedValues["note"] = style.note
        record.encryptedValues["samples"] = try? JSONEncoder().encode(
            style.samples.map { Sample(id: $0.id, text: $0.text) }
        )
        record["modified"] = modified
    }

    public static func style(from record: CKRecord) -> WritingStyle? {
        guard let (kind, name) = parse(record.recordID.recordName), kind == .style,
              let id = UUID(uuidString: name) else { return nil }
        let samples = (record.encryptedValues["samples"] as? Data)
            .flatMap { try? JSONDecoder().decode([Sample].self, from: $0) } ?? []
        return WritingStyle(
            id: id,
            name: record.encryptedValues["name"] as? String ?? "",
            note: record.encryptedValues["note"] as? String ?? "",
            samples: samples.map { StyleSample(id: $0.id, text: $0.text) }
        )
    }

    // MARK: Actions

    public static func write(_ action: CustomAction, modified: Date, into record: CKRecord) {
        record.encryptedValues["name"] = action.name
        record.encryptedValues["instruction"] = action.instruction
        record.encryptedValues["output"] = action.output.rawValue
        record["modified"] = modified
    }

    public static func action(from record: CKRecord) -> CustomAction? {
        guard let (kind, name) = parse(record.recordID.recordName), kind == .action,
              let id = UUID(uuidString: name) else { return nil }
        return CustomAction(
            id: id,
            name: record.encryptedValues["name"] as? String ?? "",
            instruction: record.encryptedValues["instruction"] as? String ?? "",
            output: (record.encryptedValues["output"] as? String).flatMap(CustomAction.Output.init(rawValue:)) ?? .paste
        )
    }

    // MARK: Settings

    /// Writes each field's value as one JSON object, and when each changed as another.
    public static func write(_ settings: SyncMerge.Settings, into record: CKRecord) {
        var values: [String: Any] = [:]
        for (name, data) in settings.fields {
            values[name] = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        }
        record.encryptedValues["values"] = try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys)
        record.encryptedValues["dates"] = try? JSONEncoder().encode(
            settings.dates.mapValues(\.timeIntervalSince1970)
        )
        record["modified"] = settings.dates.values.max() ?? SyncMerge.unknownDate
    }

    public static func settings(from record: CKRecord) -> SyncMerge.Settings? {
        guard let (kind, _) = parse(record.recordID.recordName), kind == .settings,
              let valuesData = record.encryptedValues["values"] as? Data,
              let values = (try? JSONSerialization.jsonObject(with: valuesData)) as? [String: Any],
              let datesData = record.encryptedValues["dates"] as? Data,
              let seconds = try? JSONDecoder().decode([String: Double].self, from: datesData) else { return nil }
        var fields: [String: Data] = [:]
        for (name, value) in values {
            fields[name] = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        }
        return SyncMerge.Settings(fields: fields, dates: seconds.mapValues { Date(timeIntervalSince1970: $0) })
    }
}
