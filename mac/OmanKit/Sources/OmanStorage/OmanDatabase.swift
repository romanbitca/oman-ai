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

public final class OmanDatabase: StyleStore, AppSettingsStore, UsageStore, DictationStore, ActionStore, CustomActionStore,
    Sendable {
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
        migrator.registerMigration("v3") { db in
            try db.execute(sql: """
                CREATE TABLE dictations (
                    id TEXT PRIMARY KEY,
                    created_at DOUBLE NOT NULL,
                    body TEXT NOT NULL,
                    duration DOUBLE NOT NULL,
                    model TEXT NOT NULL,
                    language TEXT,
                    app_name TEXT
                );
                CREATE INDEX dictations_created_at ON dictations(created_at);
                """)
        }
        migrator.registerMigration("v4") { db in
            try db.execute(sql: """
                CREATE TABLE writing_actions (
                    id TEXT PRIMARY KEY,
                    created_at DOUBLE NOT NULL,
                    kind TEXT NOT NULL,
                    model TEXT NOT NULL,
                    app_name TEXT,
                    applied INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX writing_actions_created_at ON writing_actions(created_at);
                ALTER TABLE api_usage ADD COLUMN kind TEXT;
                """)
        }
        migrator.registerMigration("v5") { db in
            try db.execute(sql: "ALTER TABLE writing_actions ADD COLUMN changes INTEGER")
        }
        migrator.registerMigration("v6") { db in
            try db.execute(sql: """
                CREATE TABLE dictation_counts (
                    id TEXT PRIMARY KEY,
                    created_at DOUBLE NOT NULL,
                    words INTEGER NOT NULL,
                    duration DOUBLE NOT NULL,
                    app_name TEXT
                );
                CREATE INDEX dictation_counts_created_at ON dictation_counts(created_at);
                """)
            // The transcripts kept so far are counted once, so the numbers don't start from nothing.
            let kept = try Row.fetchAll(db, sql: "SELECT id, created_at, body, duration, app_name FROM dictations")
            for row in kept {
                let body: String = row["body"]
                try db.execute(
                    sql: "INSERT INTO dictation_counts (id, created_at, words, duration, app_name) VALUES (?, ?, ?, ?, ?)",
                    arguments: [
                        row["id"] as String, row["created_at"] as Double, DictationCount.words(in: body),
                        row["duration"] as Double, row["app_name"] as String?,
                    ]
                )
            }
        }
        migrator.registerMigration("v7") { db in
            // As written is a choice too. The table before could only name a template, so choosing As written
            // meant forgetting the app, and its next panel fell back to the default template.
            try db.execute(sql: """
                CREATE TABLE app_style_choices (
                    app_key TEXT PRIMARY KEY,
                    style_id TEXT REFERENCES styles(id) ON DELETE CASCADE
                );
                INSERT INTO app_style_choices (app_key, style_id)
                    SELECT bundle_id, style_id FROM app_style_preferences;
                DROP TABLE app_style_preferences;
                """)
        }
        migrator.registerMigration("v8") { db in
            // The person's own actions. Their shortcuts are kept with the other shortcuts, in the preferences.
            try db.execute(sql: """
                CREATE TABLE custom_actions (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    instruction TEXT NOT NULL DEFAULT '',
                    output TEXT NOT NULL DEFAULT 'paste',
                    created_at DOUBLE NOT NULL
                );
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

    public func lastStyleChoice(forApp key: String) throws -> StyleChoice? {
        try writer.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT style_id FROM app_style_choices WHERE app_key = ?", arguments: [key]
            ) else { return nil }
            // A row with no template is As written, chosen.
            guard let text = row["style_id"] as String? else { return .asWritten }
            return .style(try Self.uuid(from: text))
        }
    }

    public func setLastStyleChoice(_ choice: StyleChoice?, forApp key: String) throws {
        try writer.write { db in
            guard let choice else {
                try db.execute(sql: "DELETE FROM app_style_choices WHERE app_key = ?", arguments: [key])
                return
            }
            try db.execute(
                sql: """
                    INSERT INTO app_style_choices (app_key, style_id) VALUES (?, ?)
                    ON CONFLICT(app_key) DO UPDATE SET style_id = excluded.style_id
                    """,
                arguments: [key, choice.styleID?.uuidString]
            )
        }
    }

    // MARK: CustomActionStore

    public func loadCustomActions() throws -> [CustomAction] {
        try writer.read { db in
            try Row.fetchAll(
                db, sql: "SELECT id, name, instruction, output FROM custom_actions ORDER BY created_at, rowid"
            ).map { row in
                CustomAction(
                    id: try Self.uuid(from: row["id"]),
                    name: row["name"],
                    instruction: row["instruction"],
                    // An output a newer OmanAI wrote is only read, so nothing this version can't name is pasted.
                    output: CustomAction.Output(rawValue: row["output"]) ?? .read
                )
            }
        }
    }

    public func saveCustomAction(_ action: CustomAction) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO custom_actions (id, name, instruction, output, created_at) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name, instruction = excluded.instruction, output = excluded.output
                    """,
                arguments: [
                    action.id.uuidString, action.name, action.instruction, action.output.rawValue,
                    now().timeIntervalSince1970,
                ]
            )
        }
    }

    public func deleteCustomAction(id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM custom_actions WHERE id = ?", arguments: [id.uuidString])
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
                        cache_write_5m_tokens, cache_write_1h_tokens, cost_usd, kind
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    entry.date.timeIntervalSince1970, entry.model, entry.tokens.input, entry.tokens.output,
                    entry.tokens.cacheRead, entry.tokens.cacheWrite5m, entry.tokens.cacheWrite1h, entry.cost,
                    entry.kind?.rawValue,
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
                        cache_write_5m_tokens, cache_write_1h_tokens, cost_usd, kind
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
                    cost: row["cost_usd"],
                    kind: (row["kind"] as String?).flatMap(WritingTask.Kind.init(rawValue:))
                )
            }
        }
    }

    // MARK: ActionStore

    public func recordAction(_ action: WritingAction) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO writing_actions (id, created_at, kind, model, app_name, applied, changes)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    action.id.uuidString, action.date.timeIntervalSince1970, action.kind.rawValue, action.model,
                    action.appName, action.applied, action.changes,
                ]
            )
        }
    }

    public func markActionApplied(id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE writing_actions SET applied = 1 WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func actions(since date: Date) throws -> [WritingAction] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, created_at, kind, model, app_name, applied, changes
                    FROM writing_actions WHERE created_at >= ? ORDER BY created_at, rowid
                    """,
                arguments: [date.timeIntervalSince1970]
            ).compactMap { row in
                // A kind this version doesn't know comes from a newer OmanAI, and is left out.
                guard let kind = WritingTask.Kind(rawValue: row["kind"]) else { return nil }
                return WritingAction(
                    id: try Self.uuid(from: row["id"]),
                    date: Date(timeIntervalSince1970: row["created_at"]),
                    kind: kind,
                    model: row["model"],
                    appName: row["app_name"],
                    applied: row["applied"],
                    changes: row["changes"]
                )
            }
        }
    }

    // MARK: DictationStore

    public func recordDictationCount(_ count: DictationCount) throws {
        try writer.write { db in
            try db.execute(
                sql: "INSERT INTO dictation_counts (id, created_at, words, duration, app_name) VALUES (?, ?, ?, ?, ?)",
                arguments: [count.id.uuidString, count.date.timeIntervalSince1970, count.words, count.duration, count.appName]
            )
        }
    }

    public func dictationCounts(since date: Date) throws -> [DictationCount] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, created_at, words, duration, app_name
                    FROM dictation_counts WHERE created_at >= ? ORDER BY created_at, rowid
                    """,
                arguments: [date.timeIntervalSince1970]
            ).map { row in
                DictationCount(
                    id: try Self.uuid(from: row["id"]),
                    date: Date(timeIntervalSince1970: row["created_at"]),
                    words: row["words"],
                    duration: row["duration"],
                    appName: row["app_name"]
                )
            }
        }
    }

    public func saveDictation(_ dictation: SavedDictation) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO dictations (id, created_at, body, duration, model, language, app_name)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    dictation.id.uuidString, dictation.date.timeIntervalSince1970, dictation.text,
                    dictation.duration, dictation.model, dictation.language, dictation.appName,
                ]
            )
        }
    }

    public func savedDictations() throws -> [SavedDictation] {
        try fetchDictations(limit: nil)
    }

    public func latestDictation() throws -> SavedDictation? {
        try fetchDictations(limit: 1).first
    }

    private func fetchDictations(limit: Int?) throws -> [SavedDictation] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, created_at, body, duration, model, language, app_name
                    FROM dictations ORDER BY created_at DESC, rowid DESC LIMIT ?
                    """,
                arguments: [limit ?? -1]
            ).map { row in
                SavedDictation(
                    id: try Self.uuid(from: row["id"]),
                    date: Date(timeIntervalSince1970: row["created_at"]),
                    text: row["body"],
                    duration: row["duration"],
                    model: row["model"],
                    language: row["language"],
                    appName: row["app_name"]
                )
            }
        }
    }

    public func deleteDictation(id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM dictations WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func deleteAllDictations() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM dictations")
        }
    }

    public func trimDictations(keepingNewest count: Int) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM dictations WHERE id NOT IN (
                        SELECT id FROM dictations ORDER BY created_at DESC, rowid DESC LIMIT ?
                    )
                    """,
                arguments: [max(count, 0)]
            )
        }
    }
}
