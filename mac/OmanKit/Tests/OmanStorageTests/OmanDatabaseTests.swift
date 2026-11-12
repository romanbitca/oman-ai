import Foundation
import GRDB
import OmanCore
import Testing
@testable import OmanStorage

private final class TickingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds = 0.0

    func next() -> Date {
        lock.withLock {
            seconds += 1
            return Date(timeIntervalSince1970: seconds)
        }
    }
}

private func makeDatabase() throws -> OmanDatabase {
    let clock = TickingClock()
    return try OmanDatabase.inMemory(now: { clock.next() })
}

private func createdAt(of id: UUID, in database: OmanDatabase) throws -> Double? {
    try database.writer.read { db in
        try Double.fetchOne(db, sql: "SELECT created_at FROM styles WHERE id = ?", arguments: [id.uuidString])
    }
}

private func rowCount(in table: String, of database: OmanDatabase) throws -> Int {
    try database.writer.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
    }
}

@Suite("Schema")
struct SchemaTests {
    @Test func createsExpectedTablesAndColumns() throws {
        let database = try makeDatabase()
        let columns = try database.writer.read { db in
            try ["styles", "style_samples", "app_style_choices", "settings"].map { table in
                try db.columns(in: table).map(\.name)
            }
        }

        #expect(columns == [
            ["id", "name", "note", "created_at"],
            ["id", "style_id", "body", "position"],
            ["app_key", "style_id"],
            ["key", "value"],
        ])
    }

    @Test func foreignKeysAreEnforced() throws {
        let database = try makeDatabase()
        #expect(throws: (any Error).self) {
            try database.setLastStyleChoice(.style(UUID()), forApp: "com.example.app")
        }
    }

    @Test func invalidStoredIdentifierThrowsInsteadOfCrashing() throws {
        let database = try makeDatabase()
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO styles (id, name, created_at) VALUES ('not-a-uuid', 'Broken', 1)")
        }
        #expect(throws: OmanDatabaseError.invalidIdentifier("not-a-uuid")) {
            try database.loadStyles()
        }
    }
}

@Suite("Styles")
struct StyleTests {
    @Test func startsEmpty() throws {
        #expect(try makeDatabase().loadStyles().isEmpty)
    }

    @Test func roundTripsAStyle() throws {
        let database = try makeDatabase()
        let style = WritingStyle(
            name: "Slack с коллегами",
            note: "no emoji with clients",
            samples: [
                StyleSample(text: "привет! скинь плиз отчёт 🙏"),
                StyleSample(text: "Line one\nLine two\n\n\"quoted\" and 'apostrophes'"),
            ]
        )

        try database.save(style)

        #expect(try database.loadStyles() == [style])
    }

    @Test func roundTripsAStyleWithNoSamplesAndEmptyNote() throws {
        let database = try makeDatabase()
        let style = WritingStyle(name: "New style")

        try database.save(style)

        #expect(try database.loadStyles() == [style])
    }

    @Test func preservesSampleOrder() throws {
        let database = try makeDatabase()
        let samples = ["zulu", "alpha", "mike", "alpha", "bravo"].map { StyleSample(text: $0) }
        let style = WritingStyle(name: "Ordered", samples: samples)

        try database.save(style)

        #expect(try database.loadStyles().first?.samples == samples)
    }

    @Test func keepsSamplesWithTheirOwnStyle() throws {
        let database = try makeDatabase()
        let first = WritingStyle(name: "First", samples: [StyleSample(text: "one"), StyleSample(text: "two")])
        let second = WritingStyle(name: "Second", samples: [StyleSample(text: "three")])

        try database.save(first)
        try database.save(second)

        #expect(try database.loadStyles() == [first, second])
    }

    @Test func updatingReplacesSamplesAndKeepsCreatedAt() throws {
        let database = try makeDatabase()
        var style = WritingStyle(name: "Before", note: "old", samples: [StyleSample(text: "a"), StyleSample(text: "b")])
        try database.save(style)
        let originalCreatedAt = try createdAt(of: style.id, in: database)

        style.name = "After"
        style.note = "new"
        style.samples = [StyleSample(text: "c")]
        try database.save(style)

        #expect(try database.loadStyles() == [style])
        #expect(try createdAt(of: style.id, in: database) == originalCreatedAt)
        #expect(try rowCount(in: "style_samples", of: database) == 1)
    }

    @Test func updatingDoesNotChangeStyleOrder() throws {
        let database = try makeDatabase()
        var older = WritingStyle(name: "Older")
        let newer = WritingStyle(name: "Newer")
        try database.save(older)
        try database.save(newer)

        older.name = "Older, edited last"
        try database.save(older)

        #expect(try database.loadStyles().map(\.id) == [older.id, newer.id])
    }

    @Test func ordersStylesByCreationTime() throws {
        let database = try makeDatabase()
        let names = ["Zulu", "Alpha", "Mike"]

        for name in names {
            try database.save(WritingStyle(name: name))
        }

        #expect(try database.loadStyles().map(\.name) == names)
    }

    @Test func breaksCreationTimeTiesByID() throws {
        let frozen = Date(timeIntervalSince1970: 100)
        let database = try OmanDatabase.inMemory(now: { frozen })
        let low = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

        try database.save(WritingStyle(id: high, name: "High"))
        try database.save(WritingStyle(id: low, name: "Low"))

        #expect(try database.loadStyles().map(\.id) == [low, high])
    }

    @Test func aFailedSaveLeavesTheStyleUnchanged() throws {
        let database = try makeDatabase()
        var style = WritingStyle(name: "Stable", samples: [StyleSample(text: "kept")])
        try database.save(style)
        let saved = style

        let duplicateID = UUID()
        style.name = "Should not stick"
        style.samples = [StyleSample(id: duplicateID, text: "x"), StyleSample(id: duplicateID, text: "y")]

        #expect(throws: (any Error).self) {
            try database.save(style)
        }
        #expect(try database.loadStyles() == [saved])
    }

    @Test func deleteCascadesToSamplesAndPreferences() throws {
        let database = try makeDatabase()
        let doomed = WritingStyle(name: "Doomed", samples: [StyleSample(text: "gone"), StyleSample(text: "also gone")])
        let survivor = WritingStyle(name: "Survivor", samples: [StyleSample(text: "stays")])
        try database.save(doomed)
        try database.save(survivor)
        try database.setLastStyleChoice(.style(doomed.id), forApp: "com.example.doomed")
        try database.setLastStyleChoice(.style(survivor.id), forApp: "com.example.survivor")
        try database.setLastStyleChoice(.asWritten, forApp: "com.example.plain")

        try database.deleteStyle(id: doomed.id)

        #expect(try database.loadStyles() == [survivor])
        #expect(try rowCount(in: "style_samples", of: database) == 1)
        // The app whose template is gone has no choice left. As written, which names no template, stays.
        #expect(try rowCount(in: "app_style_choices", of: database) == 2)
        #expect(try database.lastStyleChoice(forApp: "com.example.doomed") == nil)
        #expect(try database.lastStyleChoice(forApp: "com.example.survivor") == .style(survivor.id))
        #expect(try database.lastStyleChoice(forApp: "com.example.plain") == .asWritten)
    }

    @Test func deletingAnUnknownStyleDoesNothing() throws {
        let database = try makeDatabase()
        let style = WritingStyle(name: "Kept")
        try database.save(style)

        try database.deleteStyle(id: UUID())

        #expect(try database.loadStyles() == [style])
    }
}

@Suite("Last style per app")
struct LastStyleTests {
    @Test func isNilWhenAbsent() throws {
        #expect(try makeDatabase().lastStyleChoice(forApp: "com.example.app") == nil)
    }

    @Test func setsOverwritesAndClears() throws {
        let database = try makeDatabase()
        let first = WritingStyle(name: "First")
        let second = WritingStyle(name: "Second")
        try database.save(first)
        try database.save(second)
        let bundleID = "com.tinyspeck.slackmacgap"

        try database.setLastStyleChoice(.style(first.id), forApp: bundleID)
        #expect(try database.lastStyleChoice(forApp: bundleID) == .style(first.id))

        try database.setLastStyleChoice(.style(second.id), forApp: bundleID)
        #expect(try database.lastStyleChoice(forApp: bundleID) == .style(second.id))
        #expect(try rowCount(in: "app_style_choices", of: database) == 1)

        try database.setLastStyleChoice(nil, forApp: bundleID)
        #expect(try database.lastStyleChoice(forApp: bundleID) == nil)
        #expect(try rowCount(in: "app_style_choices", of: database) == 0)
    }

    @Test func asWrittenIsAChoiceOfItsOwn() throws {
        let database = try makeDatabase()
        let style = WritingStyle(name: "Slack")
        try database.save(style)
        let bundleID = "com.tinyspeck.slackmacgap"

        try database.setLastStyleChoice(.style(style.id), forApp: bundleID)
        try database.setLastStyleChoice(.asWritten, forApp: bundleID)

        // Chosen, which is not the same as nothing chosen yet.
        #expect(try database.lastStyleChoice(forApp: bundleID) == .asWritten)
        #expect(try rowCount(in: "app_style_choices", of: database) == 1)

        try database.setLastStyleChoice(.style(style.id), forApp: bundleID)
        #expect(try database.lastStyleChoice(forApp: bundleID) == .style(style.id))
    }

    @Test func isTrackedSeparatelyForEachApp() throws {
        let database = try makeDatabase()
        let first = WritingStyle(name: "First")
        let second = WritingStyle(name: "Second")
        try database.save(first)
        try database.save(second)

        try database.setLastStyleChoice(.style(first.id), forApp: "com.example.one")
        try database.setLastStyleChoice(.style(second.id), forApp: "com.example.two")

        #expect(try database.lastStyleChoice(forApp: "com.example.one") == .style(first.id))
        #expect(try database.lastStyleChoice(forApp: "com.example.two") == .style(second.id))
    }

    @Test func clearingAnAbsentPreferenceDoesNothing() throws {
        try makeDatabase().setLastStyleChoice(nil, forApp: "com.example.absent")
    }
}

@Suite("Selected model")
struct SelectedModelTests {
    @Test func defaultsToHaiku() throws {
        #expect(try makeDatabase().selectedModel() == .haiku)
    }

    @Test(arguments: WritingModel.allCases)
    func persistsEachModel(model: WritingModel) throws {
        let database = try makeDatabase()

        try database.setSelectedModel(model)

        #expect(try database.selectedModel() == model)
    }

    @Test func overwritesThePreviousSelection() throws {
        let database = try makeDatabase()

        try database.setSelectedModel(.opus)
        try database.setSelectedModel(.sonnet)

        #expect(try database.selectedModel() == .sonnet)
        #expect(try rowCount(in: "settings", of: database) == 1)
    }

    @Test func fallsBackToDefaultForUnknownValue() throws {
        let database = try makeDatabase()
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO settings (key, value) VALUES ('selected_model', 'claude-retired-1')")
        }

        #expect(try database.selectedModel() == .default)
    }
}

@Suite("File-backed database")
struct FileBackedTests {
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("oman-storage-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test func createsTheDirectoryAndDatabaseFile() throws {
        try withTemporaryDirectory { root in
            let directory = root.appendingPathComponent("nested/oman", isDirectory: true)

            _ = try OmanDatabase.open(inDirectory: directory)

            #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("writing.sqlite").path))
        }
    }

    @Test func reopeningKeepsData() throws {
        try withTemporaryDirectory { directory in
            let style = WritingStyle(name: "Persisted", note: "note", samples: [StyleSample(text: "sample")])
            do {
                let database = try OmanDatabase.open(inDirectory: directory)
                try database.save(style)
                try database.setLastStyleChoice(.style(style.id), forApp: "com.example.app")
                try database.setSelectedModel(.opus)
            }

            let reopened = try OmanDatabase.open(inDirectory: directory)

            #expect(try reopened.loadStyles() == [style])
            #expect(try reopened.lastStyleChoice(forApp: "com.example.app") == .style(style.id))
            #expect(try reopened.selectedModel() == .opus)
        }
    }
}

@Suite("Usage")
struct UsageStorageTests {
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("oman-usage-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    @Test func theUsageTableHasItsColumns() throws {
        let database = try makeDatabase()
        let columns = try database.writer.read { db in try db.columns(in: "api_usage").map(\.name) }

        #expect(columns == [
            "id", "created_at", "model", "input_tokens", "output_tokens", "cache_read_tokens",
            "cache_write_5m_tokens", "cache_write_1h_tokens", "cost_usd", "kind",
        ])
    }

    @Test func keepsEntriesAndReadsBackThoseSinceADate() throws {
        let database = try makeDatabase()
        let older = UsageEntry(
            date: Date(timeIntervalSince1970: 1_000),
            model: "claude-haiku-5-5",
            tokens: TokenUsage(input: 1, output: 2, cacheRead: 3, cacheWrite5m: 4, cacheWrite1h: 5),
            cost: 0.5
        )
        let newer = UsageEntry(
            date: Date(timeIntervalSince1970: 2_000),
            model: "claude-opus-5-5",
            tokens: TokenUsage(input: 10),
            cost: 1.25
        )
        try database.record(newer)
        try database.record(older)

        #expect(try database.usageEntries(since: Date(timeIntervalSince1970: 0)) == [older, newer])
        #expect(try database.usageEntries(since: Date(timeIntervalSince1970: 2_000)) == [newer])
        #expect(try database.usageEntries(since: Date(timeIntervalSince1970: 2_001)).isEmpty)
    }

    @Test func aDatabaseFromTheFirstVersionGainsTheTableAndKeepsItsStyles() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("writing.sqlite").path
            // The schema and migration record an earlier OmanAI left behind.
            try DatabaseQueue(path: path).write { db in
                try db.execute(sql: """
                    CREATE TABLE styles (id TEXT PRIMARY KEY, name TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', created_at DOUBLE NOT NULL);
                    CREATE TABLE style_samples (id TEXT PRIMARY KEY, style_id TEXT NOT NULL REFERENCES styles(id) ON DELETE CASCADE, body TEXT NOT NULL, position INTEGER NOT NULL);
                    CREATE TABLE app_style_preferences (bundle_id TEXT PRIMARY KEY, style_id TEXT NOT NULL REFERENCES styles(id) ON DELETE CASCADE);
                    CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                    CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                    INSERT INTO grdb_migrations VALUES ('v1');
                    INSERT INTO styles VALUES ('8D3B5C2A-0B1E-4F5A-9C3D-2E4F6A8B0C1D', 'Kept', '', 1);
                    """)
            }

            let upgraded = try OmanDatabase.open(path: path)

            #expect(try upgraded.loadStyles().map(\.name) == ["Kept"])
            try upgraded.record(UsageEntry(date: Date(), model: "claude-haiku-5-5", tokens: TokenUsage(input: 1), cost: 0))
            #expect(try upgraded.usageEntries(since: Date(timeIntervalSince1970: 0)).count == 1)
        }
    }

    @Test func theTemplateEachAppWasLeftOnSurvivesTheNewTable() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("writing.sqlite").path
            let style = WritingStyle(name: "Slack")
            let earlier = try OmanDatabase.open(path: path)
            try earlier.save(style)
            // As 0.4.3 left it: one template remembered for each of two apps, in the table that could name
            // nothing but a template.
            try earlier.writer.write { db in
                try db.execute(sql: """
                    DROP TABLE app_style_choices;
                    CREATE TABLE app_style_preferences (bundle_id TEXT PRIMARY KEY, style_id TEXT NOT NULL REFERENCES styles(id) ON DELETE CASCADE);
                    DELETE FROM grdb_migrations WHERE identifier = 'v7';
                    """)
                try db.execute(
                    sql: "INSERT INTO app_style_preferences VALUES ('com.example.one', ?), ('com.example.two', ?)",
                    arguments: [style.id.uuidString, style.id.uuidString]
                )
            }

            let upgraded = try OmanDatabase.open(path: path)

            #expect(try upgraded.lastStyleChoice(forApp: "com.example.one") == .style(style.id))
            #expect(try upgraded.lastStyleChoice(forApp: "com.example.two") == .style(style.id))
            #expect(try upgraded.lastStyleChoice(forApp: "com.example.three") == nil)
            let tables = try upgraded.writer.read { db in
                try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'app_style%'")
            }
            #expect(tables == ["app_style_choices"])
            // The new table still lets go of an app's choice when its template is deleted.
            try upgraded.deleteStyle(id: style.id)
            #expect(try upgraded.lastStyleChoice(forApp: "com.example.one") == nil)
        }
    }
}
