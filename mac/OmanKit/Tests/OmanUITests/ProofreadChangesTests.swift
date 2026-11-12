import Foundation
import OmanCore
import Testing
@testable import OmanUI

@MainActor
@Suite struct ProofreadChangesTests {
    private let typed = "sorry for the delay, the invoice was send on monday and you should recieve it untill friday"
    private let corrected = "sorry for the delay, the invoice was sent on monday and you should receive it until friday"

    private func harness(showing display: ProofreadChanges? = nil, answer: String? = nil) throws -> Harness {
        let harness = Harness()
        harness.writing.script(deltas: [answer ?? corrected])
        if let display {
            var preferences = try harness.settings.preferences()
            preferences.proofreadChanges = display
            try harness.settings.setPreferences(preferences)
        }
        return harness
    }

    private func proofread(_ harness: Harness, text: String? = nil) async -> PanelViewModel {
        let model = harness.makePanel()
        model.begin(with: SelectionCapture(app: Harness.slack, text: text ?? typed))
        model.proofread()
        await model.runningTask?.value
        return model
    }

    // MARK: The panel

    @Test func aProofreadOffersItsChangesInsteadOfTheOriginal() async throws {
        let model = await proofread(try harness())
        #expect(model.screen == .result)
        #expect(model.proofreadChanges?.count == 3)
        #expect(model.offersChanges)
        #expect(!model.offersOriginal)
        #expect(!model.showChanges)
    }

    @Test func changesAreMarkedAtOnceUnlessSettingsSayToWait() async throws {
        let atOnce = await proofread(try harness())
        #expect(atOnce.proofreadChangesDisplay == .atOnce)
        let whenAsked = await proofread(try harness(showing: .whenAsked))
        #expect(whenAsked.proofreadChangesDisplay == .whenAsked)
    }

    @Test func theShortcutForTheOriginalShowsTheChanges() async throws {
        let model = await proofread(try harness())
        let toggle = try #require(AppPreferences().combo(for: .toggleOriginal))
        #expect(model.handlePanelShortcut(toggle))
        #expect(model.showChanges)
        #expect(!model.showOriginal)
        #expect(model.handlePanelShortcut(toggle))
        #expect(!model.showChanges)
    }

    @Test func aProofreadThatChangedNothingOffersNeither() async throws {
        let model = await proofread(try harness(answer: typed))
        #expect(model.proofreadChanges?.count == 0)
        #expect(!model.offersChanges)
        #expect(!model.offersOriginal)
        let toggle = try #require(AppPreferences().combo(for: .toggleOriginal))
        #expect(!model.handlePanelShortcut(toggle))
    }

    @Test func aProofreadThatRewroteEverythingOffersTheOriginal() async throws {
        let model = await proofread(try harness(
            answer: "Apologies for the hold-up: the January statement left our office Tuesday, so expect delivery around Thursday."
        ))
        #expect(model.proofreadChanges?.isRewrite == true)
        #expect(!model.offersChanges)
        #expect(model.offersOriginal)
    }

    @Test func otherTasksKeepShowOriginal() async throws {
        let harness = try harness()
        let model = harness.makePanel()
        model.begin(with: SelectionCapture(app: Harness.slack, text: typed))
        model.rewrite()
        await model.runningTask?.value
        #expect(model.proofreadChanges == nil)
        #expect(!model.offersChanges)
        #expect(model.offersOriginal)
    }

    @Test func shownChangesStayForTheNextVersionAndGoWithBack() async throws {
        let harness = try harness()
        let model = await proofread(harness)
        model.showChanges = true
        harness.writing.script(deltas: ["Sorry for the delay, the invoice was sent on Monday and you should receive it by Friday."])
        model.tryAgain()
        await model.runningTask?.value
        #expect(model.showChanges)
        // Sorry, sent, Monday, receive, by, and Friday with its full stop.
        #expect(model.proofreadChanges?.count == 6)

        model.goBack()
        #expect(!model.showChanges)
    }

    @Test func changesAreCountedAgainstWhatThePersonWrote() async throws {
        let harness = try harness()
        let model = await proofread(harness)
        harness.writing.script(deltas: ["sorry for the delay, the invoice was sent on monday and you should receive it by friday"])
        model.adjustment = "say by friday"
        model.applyAdjustment()
        await model.runningTask?.value
        // send, recieve and untill: the last now became "by".
        #expect(model.proofreadChanges?.count == 3)
        #expect(model.proofreadChanges?.pieces.contains(.removed("untill")) == true)
        #expect(model.proofreadChanges?.pieces.contains(.added("by")) == true)
    }

    @Test func copyAndReplaceGiveTheResultWhileChangesAreShown() async throws {
        let harness = try harness()
        let model = await proofread(harness)
        model.showChanges = true
        model.copyResult()
        #expect(harness.system.copied.last == corrected)
    }

    // MARK: The marks

    @Test func newWordsAloneSpellTheResult() {
        let changes = TextChanges(from: typed, to: corrected)
        let marked = changes.marked(showingOldWords: false, underliningNewWords: false)
        #expect(String(marked.characters) == corrected)
    }

    @Test func oldWordsStandStruckThroughBeforeTheirReplacements() {
        let changes = TextChanges(from: typed, to: corrected)
        let marked = changes.marked(showingOldWords: true, underliningNewWords: false)
        #expect(String(marked.characters)
            == "sorry for the delay, the invoice was send sent on monday and you should recieve receive it untill until friday")
        let struck = marked.runs.filter { $0.swiftUI.strikethroughStyle != nil }.map { String(marked[$0.range].characters) }
        #expect(struck == ["send", "recieve", "untill"])
        let tinted = marked.runs
            .filter { $0.swiftUI.backgroundColor != nil && $0.swiftUI.strikethroughStyle == nil }
            .map { String(marked[$0.range].characters) }
        #expect(tinted == ["sent", "receive", "until"])
    }

    @Test func aWordThatWasOnlyRemovedHasNothingAfterIt() {
        let changes = TextChanges(from: "I sent the the invoice", to: "I sent the invoice")
        let marked = changes.marked(showingOldWords: true, underliningNewWords: false)
        let text = String(marked.characters)
        #expect(text.replacingOccurrences(of: "  ", with: " ").contains("the the invoice"))
        #expect(String(changes.marked(showingOldWords: false, underliningNewWords: false).characters) == "I sent the invoice")
    }

    @Test func newWordsAreUnderlinedWhenColourIsNotEnough() {
        let changes = TextChanges(from: "teh end", to: "the end")
        let marked = changes.marked(showingOldWords: false, underliningNewWords: true)
        let underlined = marked.runs.filter { $0.swiftUI.underlineStyle != nil }.map { String(marked[$0.range].characters) }
        #expect(underlined == ["the"])
    }

    @Test func voiceOverHearsEachChangeNamed() {
        let changes = TextChanges(from: "it was send on monday", to: "it was sent on monday")
        #expect(changes.spoken == "it was  removed: send,  added: sent,  on monday")
    }

    // MARK: Settings

    @Test func theChoiceIsSavedAndOlderSettingsMarkAtOnce() throws {
        let harness = Harness()
        let settings = harness.makeSettings()
        settings.reload()
        #expect(settings.preferences.proofreadChanges == .atOnce)
        settings.preference(\.proofreadChanges).wrappedValue = .whenAsked
        #expect(try harness.settings.preferences().proofreadChanges == .whenAsked)

        let older = try JSONDecoder().decode(AppPreferences.self, from: Data(#"{"keepsPanelOpen":true}"#.utf8))
        #expect(older.proofreadChanges == .atOnce)
        let saved = try JSONEncoder().encode(try harness.settings.preferences())
        #expect(try JSONDecoder().decode(AppPreferences.self, from: saved).proofreadChanges == .whenAsked)
    }
}
