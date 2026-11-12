import Foundation
import Testing
@testable import OmanCore
@testable import OmanUI

/// Control, Option and Command keys held on their own, one or several together.
@Suite struct ModifierChordTrackerTests {
    private let both = ModifierChord([.rightCommand, .rightOption])!

    private func tracker(_ chords: ModifierChord...) -> ModifierChordTracker {
        ModifierChordTracker(chords: Set(chords))
    }

    @Test func oneKeyOnItsOwnGoesDownAndUp() {
        var keys = tracker(.rightOption)
        #expect(keys.flagsChanged(held: [.rightOption], othersHeld: false) == [.down(.rightOption)])
        #expect(keys.flagsChanged(held: [], othersHeld: false) == [.up(.rightOption)])
    }

    @Test func twoKeysHeldTogetherCountOnceBothAreDown() {
        var keys = tracker(both)
        #expect(keys.flagsChanged(held: [.rightCommand], othersHeld: false).isEmpty)
        #expect(keys.flagsChanged(held: [.rightCommand, .rightOption], othersHeld: false) == [.down(both)])
        // Letting go of one of them ends it, and letting go of the other adds nothing.
        #expect(keys.flagsChanged(held: [.rightCommand], othersHeld: false) == [.up(both)])
        #expect(keys.flagsChanged(held: [], othersHeld: false).isEmpty)
    }

    @Test func theOrderTheKeysGoDownInDoesNotMatter() {
        var keys = tracker(both)
        #expect(keys.flagsChanged(held: [.rightOption], othersHeld: false).isEmpty)
        #expect(keys.flagsChanged(held: [.rightOption, .rightCommand], othersHeld: false) == [.down(both)])
    }

    @Test func aChordThatGrowsIntoAnotherOneIsReplaced() {
        var keys = tracker(.rightOption, both)
        #expect(keys.flagsChanged(held: [.rightOption], othersHeld: false) == [.down(.rightOption)])
        #expect(keys.flagsChanged(held: [.rightOption, .rightCommand], othersHeld: false) == [.otherKey, .down(both)])
        #expect(keys.flagsChanged(held: [], othersHeld: false) == [.up(both)])
    }

    @Test func anotherKeyMakesItAShortcutUntilEveryKeyIsLetGo() {
        var keys = tracker(.rightOption)
        #expect(keys.flagsChanged(held: [.rightOption], othersHeld: false) == [.down(.rightOption)])
        #expect(keys.keyDown() == [.otherKey])
        #expect(keys.flagsChanged(held: [], othersHeld: false).isEmpty)
        // A fresh press counts again.
        #expect(keys.flagsChanged(held: [.rightOption], othersHeld: false) == [.down(.rightOption)])
    }

    @Test func shiftOrFnWithTheKeysMakesItAShortcut() {
        var keys = tracker(.rightOption)
        #expect(keys.flagsChanged(held: [.rightOption], othersHeld: false) == [.down(.rightOption)])
        #expect(keys.flagsChanged(held: [.rightOption], othersHeld: true) == [.otherKey])
        #expect(keys.flagsChanged(held: [], othersHeld: false).isEmpty)
        var shifted = tracker(.rightOption)
        #expect(shifted.flagsChanged(held: [.rightOption], othersHeld: true).isEmpty)
    }

    @Test func keysThatCanGrowIntoNoChordStartNothing() {
        var keys = tracker(both)
        // Left Command is in no chord, so this press is a shortcut whatever comes next.
        #expect(keys.flagsChanged(held: [.leftCommand], othersHeld: false).isEmpty)
        #expect(keys.flagsChanged(held: [.leftCommand, .rightCommand], othersHeld: false).isEmpty)
        #expect(keys.flagsChanged(held: [.leftCommand, .rightCommand, .rightOption], othersHeld: false).isEmpty)
        #expect(keys.flagsChanged(held: [], othersHeld: false).isEmpty)
    }

    @Test func aKeyBeyondTheChordMakesItAShortcut() {
        var keys = tracker(.rightOption)
        #expect(keys.flagsChanged(held: [.rightOption], othersHeld: false) == [.down(.rightOption)])
        #expect(keys.flagsChanged(held: [.rightOption, .leftCommand], othersHeld: false) == [.otherKey])
        #expect(keys.flagsChanged(held: [.rightOption], othersHeld: false).isEmpty)
        #expect(keys.flagsChanged(held: [], othersHeld: false).isEmpty)
    }

    @Test func eachKeyIsReadFromItsOwnSideOfTheFlags() {
        #expect(ModifierKey.down(inDeviceFlags: 0x0040 | 0x0010) == [.rightOption, .rightCommand])
        #expect(ModifierKey.down(inDeviceFlags: 0x0020 | 0x0008 | 0x0001) == [.leftOption, .leftCommand, .leftControl])
        #expect(ModifierKey.down(inDeviceFlags: 0x2000) == [.rightControl])
        #expect(ModifierKey.down(inDeviceFlags: 0).isEmpty)
    }
}

@Suite struct ModifierChordTests {
    @Test func chordsAreWrittenAsMacOSWritesThem() {
        #expect(ModifierChord([.rightCommand, .rightOption])?.displayName == "Right ⌥ + Right ⌘")
        #expect(ModifierChord([.rightCommand, .leftControl])?.displayName == "Left ⌃ + Right ⌘")
        #expect(ModifierChord(.rightOption).displayName == "Right ⌥")
        #expect(ModifierChord([]) == nil)
    }

    @Test func chordsAreSavedAsListsAndSingleKeysFrom0_4_2StillLoad() throws {
        var preferences = AppPreferences()
        preferences.dictationHoldKey = ModifierChord([.rightCommand, .rightOption])
        let data = try JSONEncoder().encode(preferences)
        #expect(String(decoding: data, as: UTF8.self).contains(#""dictationHoldKey":["rightOption","rightCommand"]"#))
        #expect(try JSONDecoder().decode(AppPreferences.self, from: data).dictationHoldKey == preferences.dictationHoldKey)

        let old = try JSONDecoder().decode(
            AppPreferences.self,
            from: Data(#"{"dictationHoldKey":"rightOption","dictationLongKey":"leftCommand"}"#.utf8)
        )
        #expect(old.dictationHoldKey == ModifierChord(.rightOption))
        #expect(old.dictationLongKey == ModifierChord(.leftCommand))
        #expect(old.dictationChords == [ModifierChord(.rightOption), ModifierChord(.leftCommand)])
    }
}

@MainActor
@Suite struct KeyChordRecordingTests {
    @Test func holdingKeysAndLettingGoRecordsTheMostHeldAtOnce() {
        let harness = Harness()
        let settings = harness.makeSettings()
        settings.reload()
        settings.setDictationKeys(.rightOption, for: .dictateLong)

        settings.startRecordingKeys(for: .dictateHold)
        // Nothing starts a dictation while keys are being recorded.
        #expect(harness.system.watchedKeys.isEmpty)
        settings.keysChanged(to: [.rightCommand])
        settings.keysChanged(to: [.rightCommand, .rightOption])
        #expect(settings.keysHeld == [.rightCommand, .rightOption])
        settings.keysChanged(to: [.rightOption])
        #expect(settings.keysHeld == [.rightCommand, .rightOption])
        settings.keysChanged(to: [])

        let both = ModifierChord([.rightCommand, .rightOption])
        #expect(settings.recordingKeysFor == nil)
        #expect(settings.dictationKeys(for: .dictateHold) == both)
        #expect((try? harness.settings.preferences())?.dictationHoldKey == both)
        #expect(harness.system.watchedKeys == [ModifierChord.rightOption, both!])
    }

    @Test func stoppingKeepsTheKeysThereWere() {
        let harness = Harness()
        let settings = harness.makeSettings()
        settings.reload()
        settings.setDictationKeys(.rightOption, for: .dictateHold)

        settings.startRecordingKeys(for: .dictateHold)
        settings.keysChanged(to: [.leftCommand])
        settings.cancelKeyRecording()

        #expect(settings.recordingKeysFor == nil)
        #expect(settings.dictationKeys(for: .dictateHold) == .rightOption)
        #expect(harness.system.watchedKeys == [.rightOption])
    }
}

@MainActor
@Suite struct TwoKeyDictationTests {
    @Test func holdingTwoKeysTogetherDictatesUntilOneComesUp() async throws {
        let harness = Harness()
        let both = try #require(ModifierChord([.rightCommand, .rightOption]))
        var preferences = AppPreferences()
        preferences.dictationHoldKey = both
        try harness.settings.setPreferences(preferences)
        let controller = harness.makeDictation()
        var clock = Date(timeIntervalSince1970: 1_000)
        let keys = ModifierKeyDictation(
            controller: controller, preferences: { preferences }, holdDelay: .milliseconds(20), now: { clock }
        )

        keys.handle(.down(both)) { nil }
        #expect(await eventually { controller.phase == .listening })
        let session = try #require(harness.speech.sessions.last)
        session.willFinish(with: "Two keys")
        clock += 2
        keys.handle(.up(both)) { nil }
        #expect(await eventually { controller.phase == .idle })
        #expect(harness.system.insertCalls.map(\.text) == ["Two keys"])
    }
}
