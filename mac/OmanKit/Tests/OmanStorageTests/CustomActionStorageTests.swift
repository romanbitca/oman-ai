import Foundation
import GRDB
import OmanCore
import Testing
@testable import OmanStorage

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds = 0.0

    func next() -> Date {
        lock.withLock {
            seconds += 1
            return Date(timeIntervalSince1970: seconds)
        }
    }
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("oman-custom-action-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

@Suite("Your actions")
struct CustomActionStorageTests {
    private func makeDatabase() throws -> OmanDatabase {
        let clock = Clock()
        return try OmanDatabase.inMemory(now: { clock.next() })
    }

    private let shorter = CustomAction(name: "Make it shorter", instruction: "Cut it to half its length")
    private let summary = CustomAction(name: "Summary", instruction: "Sum this up in one line", output: .read)

    @Test func theTableHasItsColumns() throws {
        let database = try makeDatabase()
        let columns = try database.writer.read { db in try db.columns(in: "custom_actions").map(\.name) }
        #expect(columns == ["id", "name", "instruction", "output", "created_at"])
    }

    @Test func startsEmpty() throws {
        #expect(try makeDatabase().loadCustomActions().isEmpty)
    }

    @Test func keepsActionsInTheOrderTheyWereMade() throws {
        let database = try makeDatabase()
        let bullets = CustomAction(name: "Bullets", instruction: "Turn this into bullet points\nOne line each")
        try database.saveCustomAction(shorter)
        try database.saveCustomAction(summary)
        try database.saveCustomAction(bullets)
        #expect(try database.loadCustomActions() == [shorter, summary, bullets])
    }

    @Test func savingAgainChangesTheActionAndKeepsItsPlace() throws {
        let database = try makeDatabase()
        try database.saveCustomAction(shorter)
        try database.saveCustomAction(summary)

        var changed = shorter
        changed.name = "Shorter"
        changed.instruction = "Cut it to a third"
        changed.output = .read
        try database.saveCustomAction(changed)

        #expect(try database.loadCustomActions() == [changed, summary])
    }

    @Test func roundTripsAnythingThePersonTypes() throws {
        let database = try makeDatabase()
        let action = CustomAction(name: "На русский 🇷🇺", instruction: "Translate to Russian: keep \"quotes\", 'apostrophes' and <tags>.")
        try database.saveCustomAction(action)
        #expect(try database.loadCustomActions() == [action])
    }

    @Test func deletesOneActionAndLeavesTheOthers() throws {
        let database = try makeDatabase()
        try database.saveCustomAction(shorter)
        try database.saveCustomAction(summary)
        try database.deleteCustomAction(id: shorter.id)
        #expect(try database.loadCustomActions() == [summary])
        try database.deleteCustomAction(id: UUID())
        #expect(try database.loadCustomActions() == [summary])
    }

    @Test func anOutputThisVersionDoesNotKnowIsOnlyRead() throws {
        let database = try makeDatabase()
        let id = UUID()
        try database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO custom_actions (id, name, instruction, output, created_at) VALUES (?, 'Later', 'Do it', 'speak', 1)",
                arguments: [id.uuidString]
            )
        }
        #expect(try database.loadCustomActions() == [CustomAction(id: id, name: "Later", instruction: "Do it", output: .read)])
    }

    @Test func anInvalidStoredIdentifierThrowsInsteadOfCrashing() throws {
        let database = try makeDatabase()
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO custom_actions (id, name, created_at) VALUES ('not-a-uuid', 'Broken', 1)")
        }
        #expect(throws: OmanDatabaseError.invalidIdentifier("not-a-uuid")) {
            try database.loadCustomActions()
        }
    }

    @Test func aDatabaseAs045LeftItGainsTheTableAndKeepsEverythingElse() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("writing.sqlite").path
            let style = WritingStyle(name: "Slack", samples: [StyleSample(text: "hey, quick one")])
            do {
                let earlier = try OmanDatabase.open(path: path)
                try earlier.save(style)
                try earlier.setLastStyleChoice(.asWritten, forApp: "com.example.one")
                try earlier.setLastStyleChoice(.style(style.id), forApp: "com.example.two")
                try earlier.setSelectedModel(.sonnet)
                // As 0.4.5 left it: migrations up to v7, and no table for actions.
                try earlier.writer.write { db in
                    try db.execute(sql: """
                        DROP TABLE custom_actions;
                        DELETE FROM grdb_migrations WHERE identifier = 'v8';
                        """)
                }
                let migrations = try earlier.writer.read { db in
                    try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
                }
                try #require(migrations == ["v1", "v2", "v3", "v4", "v5", "v6", "v7"])
            }

            let upgraded = try OmanDatabase.open(path: path)

            #expect(try upgraded.loadCustomActions().isEmpty)
            try upgraded.saveCustomAction(shorter)
            #expect(try upgraded.loadCustomActions() == [shorter])
            #expect(try upgraded.loadStyles() == [style])
            #expect(try upgraded.lastStyleChoice(forApp: "com.example.one") == .asWritten)
            #expect(try upgraded.lastStyleChoice(forApp: "com.example.two") == .style(style.id))
            #expect(try upgraded.selectedModel() == .sonnet)
        }
    }

    @Test func aDatabaseFromTheFirstVersionGainsEveryTableUpToActions() throws {
        try withTemporaryDirectory { directory in
            let path = directory.appendingPathComponent("writing.sqlite").path
            // The schema and migration record the first OmanAI left behind.
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
            try upgraded.saveCustomAction(summary)
            #expect(try upgraded.loadCustomActions() == [summary])
        }
    }

    @Test func reopeningKeepsTheActions() throws {
        try withTemporaryDirectory { directory in
            do {
                let database = try OmanDatabase.open(inDirectory: directory)
                try database.saveCustomAction(shorter)
                try database.saveCustomAction(summary)
            }
            #expect(try OmanDatabase.open(inDirectory: directory).loadCustomActions() == [shorter, summary])
        }
    }
}
