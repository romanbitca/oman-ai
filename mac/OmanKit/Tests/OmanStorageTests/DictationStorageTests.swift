import Foundation
import GRDB
import OmanCore
import Testing
@testable import OmanStorage

@Suite("Dictations")
struct DictationStorageTests {
    private func dictation(_ text: String, at seconds: Double, app: String? = "Notes") -> SavedDictation {
        SavedDictation(
            date: Date(timeIntervalSince1970: seconds),
            text: text,
            duration: 3.5,
            model: DictationModel.parakeet.rawValue,
            language: nil,
            appName: app
        )
    }

    @Test func theTableKeepsTextButNoSound() throws {
        let database = try OmanDatabase.inMemory()
        let columns = try database.writer.read { db in try db.columns(in: "dictations").map(\.name) }
        #expect(columns == ["id", "created_at", "body", "duration", "model", "language", "app_name"])
    }

    @Test func dictationsComeBackNewestFirst() throws {
        let database = try OmanDatabase.inMemory()
        let first = dictation("First", at: 100)
        let second = SavedDictation(
            date: Date(timeIntervalSince1970: 200),
            text: "Second, in Romanian",
            duration: 12,
            model: DictationModel.whisper.rawValue,
            language: "ro",
            appName: nil
        )
        try database.saveDictation(first)
        try database.saveDictation(second)

        #expect(try database.savedDictations() == [second, first])
    }

    @Test func oneOrAllCanBeDeleted() throws {
        let database = try OmanDatabase.inMemory()
        let kept = dictation("Kept", at: 1)
        let gone = dictation("Gone", at: 2)
        try database.saveDictation(kept)
        try database.saveDictation(gone)

        try database.deleteDictation(id: gone.id)
        #expect(try database.savedDictations() == [kept])

        try database.deleteAllDictations()
        #expect(try database.savedDictations().isEmpty)
    }

    @Test func aDatabaseFromTheLastVersionGainsTheTableAndKeepsItsUsage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("oman-dictation-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("writing.sqlite").path

        let earlier = try OmanDatabase.open(path: path)
        try earlier.record(UsageEntry(date: Date(timeIntervalSince1970: 5), model: "claude-haiku-5-5", tokens: TokenUsage(input: 1), cost: 0))
        // As 0.3.6 left it: the v3 migration not yet run.
        try earlier.writer.write { db in
            try db.execute(sql: "DROP TABLE dictations; DELETE FROM grdb_migrations WHERE identifier = 'v3'")
        }

        let upgraded = try OmanDatabase.open(path: path)
        #expect(try upgraded.usageEntries(since: Date(timeIntervalSince1970: 0)).count == 1)
        try upgraded.saveDictation(dictation("After the upgrade", at: 10))
        #expect(try upgraded.savedDictations().map(\.text) == ["After the upgrade"])
    }
}
