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

    @Test func aDictationIsCountedWithoutItsWords() throws {
        let database = try OmanDatabase.inMemory()
        let columns = try database.writer.read { db in try db.columns(in: "dictation_counts").map(\.name) }
        #expect(columns == ["id", "created_at", "words", "duration", "app_name"])

        let early = DictationCount(date: Date(timeIntervalSince1970: 100), words: 12, duration: 6.5, appName: "Notes")
        let late = DictationCount(date: Date(timeIntervalSince1970: 200), words: 3, duration: 1, appName: nil)
        try database.recordDictationCount(late)
        try database.recordDictationCount(early)

        #expect(try database.dictationCounts(since: .distantPast) == [early, late])
        #expect(try database.dictationCounts(since: Date(timeIntervalSince1970: 150)) == [late])
    }

    @Test func deletingTranscriptsLeavesTheCounts() throws {
        let database = try OmanDatabase.inMemory()
        let said = dictation("Three words here", at: 100)
        try database.saveDictation(said)
        try database.recordDictationCount(DictationCount(id: said.id, date: said.date, words: 3, duration: said.duration, appName: said.appName))

        try database.deleteAllDictations()

        #expect(try database.savedDictations().isEmpty)
        #expect(try database.dictationCounts(since: .distantPast).map(\.words) == [3])
    }

    @Test func transcriptsKeptBeforeCountsExistedAreCountedOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("oman-count-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("writing.sqlite").path

        let earlier = try OmanDatabase.open(path: path)
        let first = dictation("Ship the beta on Monday", at: 100, app: "Slack")
        let second = dictation("Hello\nthere", at: 200, app: nil)
        try earlier.saveDictation(first)
        try earlier.saveDictation(second)
        // As 0.4.3 left it: transcripts kept, and nothing counted yet.
        try earlier.writer.write { db in
            try db.execute(sql: "DROP TABLE dictation_counts; DELETE FROM grdb_migrations WHERE identifier = 'v6'")
        }

        let upgraded = try OmanDatabase.open(path: path)
        #expect(try upgraded.dictationCounts(since: .distantPast) == [
            DictationCount(id: first.id, date: first.date, words: 5, duration: 3.5, appName: "Slack"),
            DictationCount(id: second.id, date: second.date, words: 2, duration: 3.5, appName: nil),
        ])
        // Opening it again counts nothing twice.
        #expect(try OmanDatabase.open(path: path).dictationCounts(since: .distantPast).count == 2)
    }
}
