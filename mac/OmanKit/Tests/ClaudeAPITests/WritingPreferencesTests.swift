import Foundation
import OmanCore
import Testing

@testable import ClaudeAPI

struct WritingPreferencesTests {
    private func body(of request: WritingRequest) throws -> [String: Any] {
        let urlRequest = try RequestBuilder.messagesRequest(for: request, apiKey: "test-key")
        let data = try #require(urlRequest.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test(arguments: [
        (WritingQuality.fast, "low"),
        (WritingQuality.balanced, "medium"),
        (WritingQuality.best, "high"),
    ])
    func qualitySetsTheEffort(quality: WritingQuality, effort: String) throws {
        let json = try body(of: WritingRequest(task: .rewrite(text: "hi", instruction: nil), quality: quality))
        #expect((json["output_config"] as? [String: Any])?["effort"] as? String == effort)
    }

    @Test func preferencesAppearInRewriteAndCompose() {
        for task in [WritingTask.rewrite(text: "hi", instruction: nil), .compose(request: "say hi", selectedText: nil)] {
            let text = PromptBuilder.userText(
                for: WritingRequest(task: task, outputLanguage: "English", customInstructions: "No exclamation marks."),
                code: "CODE"
            )
            #expect(text.contains("<preferences-CODE>Write in English.\nNo exclamation marks.</preferences-CODE>"))
        }
    }

    @Test func proofreadIgnoresPreferences() {
        let text = PromptBuilder.userText(
            for: WritingRequest(task: .proofread(text: "hi"), outputLanguage: "English", customInstructions: "Be brief."),
            code: "CODE"
        )
        #expect(!text.contains("<preferences"))
    }

    @Test func blankPreferencesAddNothing() {
        let text = PromptBuilder.userText(
            for: WritingRequest(task: .rewrite(text: "hi", instruction: nil), outputLanguage: "  ", customInstructions: ""),
            code: "CODE"
        )
        #expect(!text.contains("<preferences"))
    }

    @Test func preferencesStayOutOfTheCachedStyleBlock() {
        let style = WritingStyle(name: "Slack", samples: [StyleSample(text: "yep")])
        let plain = WritingRequest(task: .rewrite(text: "hi", instruction: nil), style: style)
        let tuned = WritingRequest(
            task: .rewrite(text: "hi", instruction: nil),
            style: style,
            outputLanguage: "English",
            customInstructions: "Be brief."
        )
        #expect(PromptBuilder.systemBlocks(for: plain).map(\.text) == PromptBuilder.systemBlocks(for: tuned).map(\.text))
    }

    @Test func onDeviceRequestsDropTheScreenshot() {
        let shot = ScreenshotAttachment(jpegData: Data([1]), pixelWidth: 1, pixelHeight: 1)
        let request = WritingRequest(
            task: .rewrite(text: "hi", instruction: nil),
            context: WritingContext(screenshot: shot),
            model: .appleOnDevice
        )
        #expect(AppleOnDeviceClient.fitted(request).context.screenshot == nil)
    }

    @Test func onDeviceRequestsKeepOnlyTheSamplesThatFit() {
        let sample = String(repeating: "a", count: AppleOnDeviceClient.sampleCharacterBudget / 2)
        let style = WritingStyle(name: "Long", samples: (0..<5).map { _ in StyleSample(text: sample) })
        let request = WritingRequest(task: .rewrite(text: "hi", instruction: nil), style: style, model: .appleOnDevice)
        #expect(AppleOnDeviceClient.fitted(request).style?.samples.count == 2)
    }

    @Test func onDeviceInstructionsCarryTheStyleExamples() {
        let style = WritingStyle(name: "Slack", note: "no emoji", samples: [StyleSample(text: "yep on it")])
        let text = AppleOnDeviceClient.instructions(
            for: WritingRequest(task: .rewrite(text: "hi", instruction: nil), style: style, model: .appleOnDevice)
        )
        #expect(text.contains("- yep on it"))
        #expect(text.contains("Also: no emoji"))
    }

    @Test func onDeviceProofreadIgnoresStyleAndPreferences() {
        let style = WritingStyle(name: "Slack", samples: [StyleSample(text: "yep on it")])
        let request = WritingRequest(
            task: .proofread(text: "hi"),
            style: style,
            model: .appleOnDevice,
            outputLanguage: "English",
            customInstructions: "Be brief."
        )
        let text = AppleOnDeviceClient.instructions(for: request)
        #expect(!text.contains("yep on it"))
        #expect(!text.contains("English"))
        #expect(!text.contains("Be brief."))
    }

    @Test func onDevicePromptUsesPlainSentencesNotTags() {
        let prompt = AppleOnDeviceClient.prompt(
            for: WritingRequest(task: .compose(request: "a thank-you note", selectedText: "the report"), model: .appleOnDevice)
        )
        #expect(prompt.contains("Write this: a thank-you note"))
        #expect(prompt.contains("For reference:\nthe report"))
        #expect(!prompt.contains("<"))
    }

    @Test func onDeviceModelNeverGoesToAnthropicHeaders() throws {
        let urlRequest = try RequestBuilder.messagesRequest(
            for: WritingRequest(task: .rewrite(text: "hi", instruction: nil), model: .appleOnDevice),
            apiKey: "test-key"
        )
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }
}
