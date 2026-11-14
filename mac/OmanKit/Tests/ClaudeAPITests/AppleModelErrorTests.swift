import Foundation
import Testing

@testable import ClaudeAPI

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleModelErrorTests {
    /// An error rebuilt from another process has only the framework's domain and a number, which mean nothing to
    /// the person.
    @Test func anErrorWithOnlyANumberIsSaidPlainly() {
        let error = NSError(domain: "FoundationModels.LanguageModelSession.GenerationError", code: -1)
        let sentence = AppleOnDeviceClient.sentence(for: error)
        #expect(sentence == "Apple's on-device model couldn't write this. Try again, or choose Claude in Settings.")
        #expect(!sentence.contains("FoundationModels"))
    }

    #if canImport(FoundationModels)
    @Test func aTextTooLongForTheModelIsSaidSo() {
        guard #available(macOS 26.0, *) else { return }
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "")
        let sentence = AppleOnDeviceClient.sentence(for: LanguageModelSession.GenerationError.exceededContextWindowSize(context))
        #expect(sentence.hasPrefix("This is too long for Apple's on-device model."))
    }
    #endif
}
