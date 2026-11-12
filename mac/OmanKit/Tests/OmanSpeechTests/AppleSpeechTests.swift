import AVFoundation
import Foundation
import Testing
@testable import OmanCore
@testable import OmanSpeech

/// Runs Apple's real model on a sentence spoken by macOS's `say`, so no microphone is needed. Off unless
/// OMAN_LIVE_SPEECH=1 is set, because the first run downloads the English model through macOS.
@Suite struct AppleSpeechTests {
    static var isOn: Bool { ProcessInfo.processInfo.environment["OMAN_LIVE_SPEECH"] == "1" }

    @Test func theLanguagesIncludeEnglish() async throws {
        guard Self.isOn, #available(macOS 26.0, *) else { return }
        let languages = await AppleSpeech.languages()
        print("Apple's languages (\(languages.count)):", languages.map(\.id).joined(separator: " "))
        #expect(languages.contains { $0.id.hasPrefix("en") })
    }

    @Test func aSpokenSentenceComesBackAsText() async throws {
        guard Self.isOn, #available(macOS 26.0, *) else { return }
        let language = DictationLanguage(id: "en-US")
        if case .needsDownload = await AppleSpeech.status(of: language) {
            try await AppleSpeech.download(language) { _ in }
        }
        #expect(await AppleSpeech.status(of: language) == .ready)

        let url = try SpokenSample.make("Please send the report to Anna before Friday. Thank you.")
        let text = try await AppleSpeech.transcribe(file: url, language: language)
        print("Apple heard:", text)
        let words = text.lowercased()
        #expect(words.contains("report"))
        #expect(words.contains("friday"))
    }
}

enum SpokenSample {
    /// A sentence spoken by macOS's built-in voice, written to a temporary file.
    static func make(_ sentence: String, voice: String? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oman-speech-\(UUID().uuidString).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = (voice.map { ["-v", $0] } ?? []) + ["-o", url.path, sentence]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else {
            throw DictationError.failed("say failed with status \(say.terminationStatus)")
        }
        return url
    }
}
