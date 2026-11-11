import Foundation
import OmanCore
import Testing
@testable import OmanUI

@MainActor
@Suite struct SettingsViewModelTests {
    @Test func reloadReadsEverything() throws {
        let harness = Harness()
        try harness.settings.setSelectedModel(.sonnet)
        harness.system.isScreenCaptureGranted = false
        harness.system.isLaunchAtLoginEnabled = true
        let saved = WritingStyle(name: "Mail")
        harness.styles.seed([saved])

        let model = harness.makeSettings()
        model.reload()
        #expect(model.hasAPIKey)
        #expect(model.selectedModel == .sonnet)
        #expect(model.isAccessibilityGranted)
        #expect(model.isScreenCaptureGranted == false)
        #expect(model.isLaunchAtLogin)
        #expect(model.styles == [saved])
        #expect(model.selectedStyleID == saved.id)
    }

    @Test func saveValidatesBeforeStoringTheKey() async {
        let harness = Harness(key: nil)
        let model = harness.makeSettings()
        model.reload()
        #expect(model.hasAPIKey == false)

        model.apiKeyDraft = " sk-new "
        await model.saveAPIKey()
        #expect(harness.writing.validations == ["sk-new"])
        #expect(harness.keys.current == "sk-new")
        #expect(model.hasAPIKey)
        #expect(model.apiKeyDraft.isEmpty)
        #expect(model.apiKeyError == nil)
    }

    @Test func invalidKeyIsNotSaved() async {
        let harness = Harness(key: nil)
        harness.writing.scriptValidation(error: WritingError.invalidAPIKey)
        let model = harness.makeSettings()
        model.reload()
        model.apiKeyDraft = "bad"
        await model.saveAPIKey()
        #expect(harness.keys.current == nil)
        #expect(model.hasAPIKey == false)
        #expect(model.apiKeyError == WritingError.invalidAPIKey.localizedDescription)
        #expect(model.apiKeyDraft == "bad")
    }

    @Test func removeDeletesTheKey() {
        let harness = Harness()
        let model = harness.makeSettings()
        model.reload()
        model.removeAPIKey()
        #expect(harness.keys.current == nil)
        #expect(model.hasAPIKey == false)
    }

    @Test func modelChangePersists() throws {
        let harness = Harness()
        let model = harness.makeSettings()
        model.reload()
        #expect(model.selectedModel == .haiku)
        model.setModel(.opus)
        #expect(model.selectedModel == .opus)
        #expect(try harness.settings.selectedModel() == .opus)
    }

    @Test func launchAtLoginGoesThroughTheSystem() {
        let harness = Harness()
        let model = harness.makeSettings()
        model.reload()
        model.setLaunchAtLogin(true)
        #expect(harness.system.isLaunchAtLoginEnabled)
        #expect(model.isLaunchAtLogin)
    }

    @Test func createStyleSavesAndSelectsIt() throws {
        let harness = Harness()
        let model = harness.makeSettings()
        model.reload()
        model.createStyle()
        let created = try #require(harness.styles.styles.first)
        #expect(created.name == "New style")
        #expect(model.selectedStyleID == created.id)
        #expect(harness.styles.saves == 1)
    }

    @Test func addAndRemoveSampleAutosave() throws {
        let harness = Harness()
        let model = harness.makeSettings()
        model.reload()
        model.createStyle()

        model.newSampleText = "  first message here  "
        model.addSample()
        #expect(model.newSampleText.isEmpty)
        var stored = try #require(harness.styles.styles.first)
        #expect(stored.samples.map(\.text) == ["first message here"])
        #expect(model.sampleSummary == "1 message, 3 words")

        model.newSampleText = "second"
        model.addSample()
        stored = try #require(harness.styles.styles.first)
        #expect(stored.samples.count == 2)
        #expect(model.sampleSummary == "2 messages, 4 words")

        model.removeSample(id: stored.samples[0].id)
        stored = try #require(harness.styles.styles.first)
        #expect(stored.samples.map(\.text) == ["second"])
    }

    @Test func blankSampleIsIgnored() throws {
        let harness = Harness()
        let model = harness.makeSettings()
        model.reload()
        model.createStyle()
        let saves = harness.styles.saves
        model.newSampleText = "   "
        model.addSample()
        #expect(harness.styles.saves == saves)
    }

    @Test func nameAndNoteAutosave() throws {
        let harness = Harness()
        let model = harness.makeSettings()
        model.reload()
        model.createStyle()
        model.updateName("Slack with colleagues")
        model.updateNote("no emoji with clients")
        let stored = try #require(harness.styles.styles.first)
        #expect(stored.name == "Slack with colleagues")
        #expect(stored.note == "no emoji with clients")
    }

    @Test func deleteRemovesAndSelectsNext() {
        let harness = Harness()
        let first = WritingStyle(name: "A")
        let second = WritingStyle(name: "B")
        harness.styles.seed([first, second])
        let model = harness.makeSettings()
        model.reload()
        #expect(model.selectedStyleID == first.id)
        model.deleteSelectedStyle()
        #expect(harness.styles.styles == [second])
        #expect(model.selectedStyleID == second.id)
        model.deleteSelectedStyle()
        #expect(model.selectedStyleID == nil)
        #expect(model.styles.isEmpty)
    }

    @Test func tryItStreamsARewriteWithTheCurrentStyle() async throws {
        let harness = Harness()
        try harness.settings.setSelectedModel(.sonnet)
        let model = harness.makeSettings()
        model.reload()
        model.createStyle()
        model.newSampleText = "yo"
        model.addSample()
        model.tryItText = " can you send it "
        model.tryIt()
        #expect(model.isTrying)
        await model.tryTask?.value

        let request = try #require(harness.writing.requests.last)
        #expect(request.task == .rewrite(text: "can you send it", instruction: nil))
        #expect(request.style == model.selectedStyle)
        #expect(request.model == .sonnet)
        #expect(model.tryItResult == "Hello world")
        #expect(model.isTrying == false)
    }

    @Test func tryItShowsErrorsInline() async {
        let harness = Harness()
        harness.writing.script(deltas: ["partial"], error: WritingError.overloaded)
        let model = harness.makeSettings()
        model.reload()
        model.createStyle()
        model.tryItText = "hello"
        model.tryIt()
        await model.tryTask?.value
        #expect(model.tryItResult.isEmpty)
        #expect(model.tryItError == WritingError.overloaded.localizedDescription)
        #expect(model.isTrying == false)
    }

    @Test func tryItWithoutKeyExplains() {
        let harness = Harness(key: nil)
        let model = harness.makeSettings()
        model.reload()
        model.createStyle()
        model.tryItText = "hello"
        model.tryIt()
        #expect(model.tryItError == WritingError.missingAPIKey.localizedDescription)
        #expect(harness.writing.requests.isEmpty)
    }

    @Test func selectingAnotherStyleClearsTheEditorDrafts() {
        let harness = Harness()
        let first = WritingStyle(name: "A")
        let second = WritingStyle(name: "B")
        harness.styles.seed([first, second])
        let model = harness.makeSettings()
        model.reload()
        model.newSampleText = "unsent"
        model.tryItText = "unsent"
        model.selectStyle(second.id)
        #expect(model.selectedStyleID == second.id)
        #expect(model.newSampleText.isEmpty)
        #expect(model.tryItText.isEmpty)
    }
}
