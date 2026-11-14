import Foundation
import OmanCore

/// The settings that follow the person from one device to another. What belongs to a device stays on it: the writing
/// model, the theme, the panel, the dictation model and its language, keys, pill, microphone and sounds, and the
/// shortcuts.
public struct SharedSettings: Codable, Equatable, Sendable {
    public var quality: WritingQuality
    public var outputLanguage: String
    public var customInstructions: String
    public var defaultStyleID: UUID?
    public var remembersStylePerApp: Bool
    public var proofreadChanges: ProofreadChanges
    public var dictationWords: [String]
    public var removesFillerWords: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case quality, outputLanguage, customInstructions, defaultStyleID, remembersStylePerApp, proofreadChanges,
            dictationWords, removesFillerWords
    }

    public init(_ preferences: AppPreferences) {
        quality = preferences.quality
        outputLanguage = preferences.outputLanguage
        customInstructions = preferences.customInstructions
        defaultStyleID = preferences.defaultStyleID
        remembersStylePerApp = preferences.remembersStylePerApp
        proofreadChanges = preferences.proofreadChanges
        dictationWords = preferences.dictationWords
        removesFillerWords = preferences.removesFillerWords
    }

    /// Takes these settings into a device's own, and leaves the rest of them as they are.
    public func apply(to preferences: inout AppPreferences) {
        preferences.quality = quality
        preferences.outputLanguage = outputLanguage
        preferences.customInstructions = customInstructions
        preferences.defaultStyleID = defaultStyleID
        preferences.remembersStylePerApp = remembersStylePerApp
        preferences.proofreadChanges = proofreadChanges
        preferences.dictationWords = dictationWords
        preferences.removesFillerWords = removesFillerWords
    }

    /// The names of the fields, as they are kept in iCloud.
    public static var fieldNames: [String] { CodingKeys.allCases.map(\.rawValue) }

    /// Each field as JSON of its own, keyed by its name. A field with no value is JSON's null.
    public func fields() -> [String: Data] {
        guard let object = Self.object(of: self) else { return [:] }
        var result: [String: Data] = [:]
        for name in Self.fieldNames {
            result[name] = try? JSONSerialization.data(
                withJSONObject: object[name] ?? NSNull(),
                options: [.fragmentsAllowed, .sortedKeys]
            )
        }
        return result
    }

    /// These settings with the given fields put in, one at a time. A field this version doesn't know, or whose value
    /// it can't read, such as a choice added in a later version, keeps this device's value and is left out of the
    /// names returned.
    public func replacing(_ fields: [String: Data]) -> (settings: SharedSettings, replaced: Set<String>) {
        var current = self
        var replaced: Set<String> = []
        for name in Self.fieldNames {
            guard let data = fields[name],
                  let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
                  var object = Self.object(of: current) else { continue }
            object[name] = value
            guard let joined = try? JSONSerialization.data(withJSONObject: object),
                  let candidate = try? JSONDecoder().decode(SharedSettings.self, from: joined) else { continue }
            current = candidate
            replaced.insert(name)
        }
        return (current, replaced)
    }

    private static func object(of settings: SharedSettings) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(settings) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
