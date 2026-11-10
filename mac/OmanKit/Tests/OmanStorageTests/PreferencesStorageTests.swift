import Foundation
import OmanCore
import Testing
@testable import OmanStorage

struct PreferencesStorageTests {
    @Test func missingPreferencesGiveDefaults() throws {
        let database = try OmanDatabase.inMemory()
        #expect(try database.preferences() == AppPreferences())
    }

    @Test func preferencesRoundTrip() throws {
        let database = try OmanDatabase.inMemory()
        var preferences = AppPreferences()
        preferences.appearance = .dark
        preferences.quality = .best
        preferences.outputLanguage = "Русский"
        preferences.customInstructions = "No exclamation marks."
        preferences.defaultStyleID = UUID()
        preferences.remembersStylePerApp = false
        preferences.includesScreenByDefault = true
        preferences.keepsPanelOpen = true
        preferences.setCombo(KeyCombo(keyCode: 15, modifiers: KeyCombo.option), for: .style(UUID()))
        preferences.setCombo(nil, for: .acceptResult)

        try database.setPreferences(preferences)
        #expect(try database.preferences() == preferences)
    }

    @Test func savingTwiceKeepsTheLatest() throws {
        let database = try OmanDatabase.inMemory()
        var preferences = AppPreferences()
        preferences.quality = .balanced
        try database.setPreferences(preferences)
        preferences.quality = .best
        try database.setPreferences(preferences)
        #expect(try database.preferences().quality == .best)
    }

    @Test func corruptPreferencesFallBackToDefaults() throws {
        let database = try OmanDatabase.inMemory()
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO settings (key, value) VALUES ('app_preferences', 'not json')")
        }
        #expect(try database.preferences() == AppPreferences())
    }

    @Test func theAppleModelChoicePersists() throws {
        let database = try OmanDatabase.inMemory()
        try database.setSelectedModel(.appleOnDevice)
        #expect(try database.selectedModel() == .appleOnDevice)
    }
}
