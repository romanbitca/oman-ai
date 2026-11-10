import Foundation
import OmanCore

public final class OmanDatabase: StyleStore, AppSettingsStore, Sendable {
    public static func openDefault() throws -> OmanDatabase { OmanDatabase() }

    private init() {}

    public func loadStyles() throws -> [WritingStyle] { [] }
    public func save(_ style: WritingStyle) throws {}
    public func deleteStyle(id: UUID) throws {}
    public func lastStyleID(forBundleID bundleID: String) throws -> UUID? { nil }
    public func setLastStyleID(_ id: UUID?, forBundleID bundleID: String) throws {}
    public func selectedModel() throws -> ClaudeModel { .default }
    public func setSelectedModel(_ model: ClaudeModel) throws {}
}

public struct KeychainAPIKeyStore: APIKeyStore {
    public init() {}

    public func loadAPIKey() throws -> String? { nil }
    public func saveAPIKey(_ key: String) throws {}
    public func deleteAPIKey() throws {}
}
