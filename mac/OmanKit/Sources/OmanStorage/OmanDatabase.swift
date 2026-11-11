import Foundation
import GRDB
import OmanCore

enum OmanDatabaseError: LocalizedError, Equatable {
    case invalidIdentifier(String)

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier(let value):
            "The database contains an invalid identifier: \(value)"
        }
    }
}

public final class OmanDatabase: StyleStore, AppSettingsStore, UsageStore, Sendable {
    private static let selectedModelKey = "selected_model"
    private static let preferencesKey = "app_preferences"

    let writer: any DatabaseWriter
    private let now: @Sendable () -> Date

    public static func openDefault() throws -> OmanDatabase {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try open(inDirectory: applicationSupport.appendingPathComponent("oman", isDirectory: true))
    }

    static func open(
        inDirectory directory: URL,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> OmanDatabase {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try open(path: directory.appendingPathComponent("writing.sqlite").path, now: now)
    }

    static func open(
        path: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> OmanDatabase {
        try OmanDatabase(writer: DatabaseQueue(path: path), now: now)
    }

    static func inMemory(now: @escaping @Sendable () -> Date = { Date() }) throws -> OmanDatabase {
        try OmanDatabase(writer: DatabaseQueue(), now: now)
    }

    private init(writer: any DatabaseWriter, now: @escaping @Sendable () -> Date) throws {
        self.writer = writer
        self.now = now
        try Self.migrator.migrate(writer)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE styles (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    note TEXT NOT NULL DEFAULT '',
                    created_at DOUBLE NOT NULL
                );
                CREATE TABLE style_samples (
                    id TEXT PRIMARY KEY,
                    style_id TEXT NOT NULL REFERENCES styles(id) ON DELETE CASCADE,
                    body TEXT NOT NULL,
                    position INTEGER NOT NULL
                );
                CREATE TABLE app_style_preferences (
                    bundle_id TEXT PRIMARY KEY,
                    style_id TEXT NOT NULL REFERENCES styles(id) ON DELETE CASCADE
                );
                CREATE TABLE settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                """)
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: """
                CREATE TABLE api_usage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    created_at DOUBLE NOT NULL,
                    model TEXT NOT NULL,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL,
                    cache_read_tokens INTEGER NOT NULL,
                    cache_write_5m_tokens INTEGER NOT NULL,
                    cache_write_1h_tokens INTEGER NOT NULL,
                    cost_usd DOUBLE NOT NULL
                );
                CREATE INDEX api_usage_created_at ON api_usage(created_at);
                """)
        }
        return migrator
    }

    private static func uuid(from text: String) throws -> UUID {
        guard let id = UUID(uuidString: text) else {
            throw OmanDatabaseError.invalidIdentifier(text)
        }
        return id
    }

    // MARK: StyleStore

    public func loadStyles() throws -> [WritingStyle] {
        try writer.read { db in
            let styleRows = try Row.fetchAll(db, sql: "SELECT id, name, note FROM styles ORDER BY created_at, id")
            let sampleRows = try Row.fetchAll(db, sql: "SELECT id, style_id, body FROM style_samples ORDER BY position")

            var samplesByStyle: [String: [StyleSample]] = [:]
            for row in sampleRows {
                let styleID: String = row["style_id"]
                let id = try Self.uuid(from: row["id"])
                samplesByStyle[styleID, default: []].append(StyleSample(id: id, text: row["body"]))
            }

            return try styleRows.map { row in
                let id: String = row["id"]
                return WritingStyle(
                    id: try Self.uuid(from: id),
                    name: row["name"],
                    note: row["note"],
                    samples: samplesByStyle[id] ?? []
                )
            }
        }
    }

    public func save(_ style: WritingStyle) throws {
        let id = style.id.uuidString
        let createdAt = now().timeIntervalSince1970
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO styles (id, name, note, created_at) VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET name = excluded.name, note = excluded.note
                    """,
                arguments: [id, style.name, style.note, createdAt]
            )
            try db.execute(sql: "DELETE FROM style_samples WHERE style_id = ?", arguments: [id])
            for (position, sample) in style.samples.enumerated() {
                try db.execute(
                    sql: "INSERT INTO style_samples (id, style_id, body, position) VALUES (?, ?, ?, ?)",
                    arguments: [sample.id.uuidString, id, sample.text, position]
                )
            }
        }
    }

    public func deleteStyle(id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM styles WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func lastStyleID(forBundleID bundleID: String) throws -> UUID? {
        let text = try writer.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT style_id FROM app_style_preferences WHERE bundle_id = ?",
                arguments: [bundleID]
            )
        }
        return try text.map(Self.uuid(from:))
    }

    public func setLastStyleID(_ id: UUID?, forBundleID bundleID: String) throws {
        try writer.write { db in
            guard let id else {
                try db.execute(sql: "DELETE FROM app_style_preferences WHERE bundle_id = ?", arguments: [bundleID])
                return
            }
            try db.execute(
                sql: """
                    INSERT INTO app_style_preferences (bundle_id, style_id) VALUES (?, ?)
                    ON CONFLICT(bundle_id) DO UPDATE SET style_id = excluded.style_id
                    """,
                arguments: [bundleID, id.uuidString]
            )
        }
    }

    // MARK: AppSettingsStore

    public func selectedModel() throws -> WritingModel {
        let value = try writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [Self.selectedModelKey])
        }
        return value.flatMap(WritingModel.init(rawValue:)) ?? .default
    }

    public func setSelectedModel(_ model: WritingModel) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [Self.selectedModelKey, model.rawValue]
            )
        }
    }

    public func preferences() throws -> AppPreferences {
        let value = try writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [Self.preferencesKey])
        }
        guard let value, let decoded = try? JSONDecoder().decode(AppPreferences.self, from: Data(value.utf8)) else {
            return AppPreferences()
        }
        return decoded
    }

    public func setPreferences(_ preferences: AppPreferences) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(preferences), as: UTF8.self)
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO settings (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [Self.preferencesKey, json]
            )
        }
    }

    // MARK: UsageStore

    public func record(_ entry: UsageEntry) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO api_usage (
                        created_at, model, input_tokens, output_tokens, cache_read_tokens,
                        cache_write_5m_tokens, cache_write_1h_tokens, cost_usd
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    entry.date.timeIntervalSince1970, entry.model, entry.tokens.input, entry.tokens.output,
                    entry.tokens.cacheRead, entry.tokens.cacheWrite5m, entry.tokens.cacheWrite1h, entry.cost,
                ]
            )
        }
    }

    public func usageEntries(since date: Date) throws -> [UsageEntry] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT created_at, model, input_tokens, output_tokens, cache_read_tokens,
                        cache_write_5m_tokens, cache_write_1h_tokens, cost_usd
                    FROM api_usage WHERE created_at >= ? ORDER BY created_at, id
                    """,
                arguments: [date.timeIntervalSince1970]
            ).map { row in
                UsageEntry(
                    date: Date(timeIntervalSince1970: row["created_at"]),
                    model: row["model"],
                    tokens: TokenUsage(
                        input: row["input_tokens"],
                        output: row["output_tokens"],
                        cacheRead: row["cache_read_tokens"],
                        cacheWrite5m: row["cache_write_5m_tokens"],
                        cacheWrite1h: row["cache_write_1h_tokens"]
                    ),
                    cost: row["cost_usd"]
                )
            }
        }
    }
}
