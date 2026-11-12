import Foundation
import Testing
@testable import OmanCore
@testable import OmanStorage

@Suite struct ActionStorageTests {
    private func action(_ kind: WritingTask.Kind, at seconds: TimeInterval, app: String? = "Slack") -> WritingAction {
        WritingAction(date: Date(timeIntervalSince1970: seconds), kind: kind, model: "claude-haiku-5-5", appName: app)
    }

    @Test func keepsWhatWasWrittenAndWhenItWasPutBack() throws {
        let database = try OmanDatabase.inMemory()
        let rewrite = action(.rewrite, at: 2_000)
        let explain = action(.explain, at: 1_000, app: nil)
        try database.recordAction(rewrite)
        try database.recordAction(explain)

        #expect(try database.actions(since: .distantPast) == [explain, rewrite])
        #expect(try database.actions(since: Date(timeIntervalSince1970: 1_500)) == [rewrite])

        try database.markActionApplied(id: rewrite.id)
        var applied = rewrite
        applied.applied = true
        #expect(try database.actions(since: .distantPast) == [explain, applied])
    }

    @Test func aKindFromANewerVersionIsLeftOut() throws {
        let database = try OmanDatabase.inMemory()
        try database.recordAction(action(.proofread, at: 1))
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO writing_actions (id, created_at, kind, model, app_name, applied)
                VALUES ('\(UUID().uuidString)', 2, 'translate', 'claude-haiku-5-5', NULL, 0)
                """)
        }
        #expect(try database.actions(since: .distantPast).map(\.kind) == [.proofread])
    }

    @Test func usageKeepsWhatEachRequestWasFor() throws {
        let database = try OmanDatabase.inMemory()
        let entry = UsageEntry(
            date: Date(timeIntervalSince1970: 10), model: "claude-haiku-5-5", tokens: TokenUsage(input: 1), cost: 0.01,
            kind: .proofread
        )
        try database.record(entry)
        #expect(try database.usageEntries(since: .distantPast) == [entry])
    }

    @Test func aDatabaseFromTheLastVersionGainsActionsAndKeepsItsUsage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("oman-action-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("writing.sqlite").path

        let earlier = try OmanDatabase.open(path: path)
        // As 0.4.0 left it: the v4 migration not yet run, and a request recorded without its kind.
        try earlier.writer.write { db in
            try db.execute(sql: """
                DROP TABLE writing_actions;
                CREATE TABLE api_usage_old AS SELECT id, created_at, model, input_tokens, output_tokens,
                    cache_read_tokens, cache_write_5m_tokens, cache_write_1h_tokens, cost_usd FROM api_usage;
                DROP TABLE api_usage;
                ALTER TABLE api_usage_old RENAME TO api_usage;
                INSERT INTO api_usage (created_at, model, input_tokens, output_tokens, cache_read_tokens,
                    cache_write_5m_tokens, cache_write_1h_tokens, cost_usd)
                VALUES (5, 'claude-haiku-5-5', 1, 0, 0, 0, 0, 0.5);
                DELETE FROM grdb_migrations WHERE identifier = 'v4';
                """)
        }

        let upgraded = try OmanDatabase.open(path: path)
        let usage = try upgraded.usageEntries(since: .distantPast)
        #expect(usage.count == 1)
        #expect(usage.first?.kind == nil)
        try upgraded.recordAction(action(.compose, at: 6))
        #expect(try upgraded.actions(since: .distantPast).map(\.kind) == [.compose])
    }
}
