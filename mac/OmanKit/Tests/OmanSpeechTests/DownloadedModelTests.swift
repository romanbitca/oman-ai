import Foundation
import Testing
@testable import OmanCore
@testable import OmanSpeech

/// Downloads Parakeet and Whisper and runs them on sentences spoken by macOS's `say`, through the same live path
/// the microphone uses. Off unless OMAN_LIVE_SPEECH=1 is set: the two downloads come to about 1.3 GB.
/// OMAN_SPEECH_MODELS sets where they go; by default a folder in the temporary directory, kept between runs.
@Suite(.serialized) struct DownloadedModelTests {
    static var isOn: Bool { ProcessInfo.processInfo.environment["OMAN_LIVE_SPEECH"] == "1" }

    static var modelsDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["OMAN_SPEECH_MODELS"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("oman-speech-models", isDirectory: true)
    }

    private static let english = "Please send the report to Anna before Friday. Thank you."

    @Test func parakeetHearsEnglishAndShowsWordsOnTheWay() async throws {
        guard Self.isOn else { return }
        let engine = ParakeetEngine(root: Self.modelsDirectory.appendingPathComponent("parakeet"))
        if await !engine.isDownloaded {
            let started = Date()
            try await engine.download { _ in }
            print("Parakeet downloaded and loaded in \(Int(Date().timeIntervalSince(started))) s")
        }
        #expect(await engine.isDownloaded)

        let url = try SpokenSample.make(Self.english)
        let started = Date()
        let (live, text) = try await engine.transcribe(file: url)
        print("Parakeet heard in \(String(format: "%.1f", Date().timeIntervalSince(started))) s:", text)
        print("Parakeet live:", live.map(\.text))
        #expect(text.lowercased().contains("report"))
        #expect(text.lowercased().contains("friday"))
    }

    @Test func parakeetWorksOutAnotherLanguage() async throws {
        guard Self.isOn else { return }
        let engine = ParakeetEngine(root: Self.modelsDirectory.appendingPathComponent("parakeet"))
        guard await engine.isDownloaded else { return }
        let url = try SpokenSample.make("Bonjour, je voudrais réserver une table pour deux personnes ce soir.", voice: "Amélie")
        let (_, text) = try await engine.transcribe(file: url)
        print("Parakeet heard French:", text)
        #expect(text.lowercased().contains("table"))
    }

    @Test func whisperHearsEnglishAndShowsWordsOnTheWay() async throws {
        guard Self.isOn else { return }
        let engine = WhisperEngine(root: Self.modelsDirectory.appendingPathComponent("whisper"))
        if await !engine.isDownloaded {
            let started = Date()
            try await engine.download { _ in }
            print("Whisper downloaded and loaded in \(Int(Date().timeIntervalSince(started))) s")
        }
        #expect(await engine.isDownloaded)

        let url = try SpokenSample.make(Self.english)
        let started = Date()
        let (session, feeding) = try await WhisperDictationSession.start(engine: engine, language: .automatic, file: url)
        let collector = Task {
            var seen: [String] = []
            for await update in session.updates {
                if case .transcript(let live) = update { seen.append(live.text) }
            }
            return seen
        }
        await feeding.value
        let text = try await session.finish()
        print("Whisper heard in \(String(format: "%.1f", Date().timeIntervalSince(started))) s:", text)
        print("Whisper live:", await collector.value)
        #expect(text.lowercased().contains("report"))
        #expect(text.lowercased().contains("friday"))
    }

    @Test func whisperFollowsTheChosenLanguage() async throws {
        guard Self.isOn else { return }
        let engine = WhisperEngine(root: Self.modelsDirectory.appendingPathComponent("whisper"))
        guard await engine.isDownloaded else { return }
        let url = try SpokenSample.make("Bonjour, je voudrais réserver une table pour deux personnes ce soir.", voice: "Amélie")
        let segments = try await engine.transcribe(SpeechAudio.samples(ofFile: url), language: DictationLanguage(id: "fr"))
        let text = segments.map(\.text).joined(separator: " ")
        print("Whisper heard French:", text)
        #expect(text.lowercased().contains("table"))
    }

    @Test func silenceGivesNoWords() async throws {
        guard Self.isOn else { return }
        let engine = WhisperEngine(root: Self.modelsDirectory.appendingPathComponent("whisper"))
        guard await engine.isDownloaded else { return }
        let url = try SpokenSample.make("[[slnc 3000]]")
        let (session, feeding) = try await WhisperDictationSession.start(engine: engine, language: .automatic, file: url)
        await feeding.value
        let text = try await session.finish()
        print("Whisper heard in silence: \"\(text)\"")
        #expect(text.isEmpty)
    }
}
