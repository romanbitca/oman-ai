import Foundation
import Testing
@testable import OmanCore
@testable import OmanSpeech

/// Downloads the models and runs them on sentences spoken by macOS's `say`, through the same live path the
/// microphone uses, a tenth of a second at a time. Off unless OMAN_LIVE_SPEECH=1 is set: the downloads come to
/// about 4 GB. OMAN_SPEECH_MODELS sets where they go; by default a folder in the temporary directory, kept
/// between runs. OMAN_LIVE_ONLY takes a comma-separated list of parakeetEnglish, nemotron, parakeet and whisper,
/// and of the identifiers of the other models that read again: parakeet-tdt-v2, parakeet-redux, whisper-small and
/// whisper-large-v3.
@Suite(.serialized) struct DownloadedModelTests {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static func isOn(_ name: String) -> Bool {
        guard environment["OMAN_LIVE_SPEECH"] == "1" else { return false }
        guard let only = environment["OMAN_LIVE_ONLY"], !only.isEmpty else { return true }
        return only.split(separator: ",").contains { $0 == name }
    }

    static var modelsDirectory: URL {
        if let path = environment["OMAN_SPEECH_MODELS"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("oman-speech-models", isDirectory: true)
    }

    private static let english = "Please send the report to Anna before Friday. Thank you."
    private static let french = "Bonjour, je voudrais réserver une table pour deux personnes ce soir."

    private func timed<T>(_ label: String, _ body: () async throws -> T) async rethrows -> T {
        let started = Date()
        let value = try await body()
        print("\(label) took \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        return value
    }

    @Test func parakeetUnifiedStreamsEnglish() async throws {
        guard Self.isOn("parakeetEnglish") else { return }
        let engine = StreamingEngine(kind: .parakeetEnglish, root: Self.modelsDirectory.appendingPathComponent("parakeet-unified-en"))
        if await !engine.isDownloaded {
            try await timed("Parakeet Unified download") { try await engine.download { _ in } }
        }
        let url = try SpokenSample.make(Self.english)
        let (live, text, first) = try await engine.transcribe(file: url, language: DictationLanguage(id: "en"))
        print("Parakeet Unified heard:", text)
        print("Parakeet Unified first words after \(first.map { String(format: "%.2f", $0) } ?? "never") s; live:", live)
        #expect(text.lowercased().contains("report"))
        #expect(text.lowercased().contains("friday"))
        #expect((first ?? 99) < 3)
        #expect(live.count > 2)
    }

    @Test func nemotronStreamsEnglishAndFrench() async throws {
        guard Self.isOn("nemotron") else { return }
        let engine = StreamingEngine(kind: .nemotron, root: Self.modelsDirectory.appendingPathComponent("nemotron-unified"))
        if await !engine.isDownloaded {
            try await timed("Nemotron download") { try await engine.download { _ in } }
        }
        let url = try SpokenSample.make(Self.english)
        let (live, text, first) = try await engine.transcribe(file: url, language: .automatic)
        print("Nemotron heard:", text)
        print("Nemotron first words after \(first.map { String(format: "%.2f", $0) } ?? "never") s; live:", live)
        #expect(text.lowercased().contains("report"))
        #expect((first ?? 99) < 3)

        let frenchURL = try SpokenSample.make(Self.french, voice: "Amélie")
        let (_, frenchText, _) = try await engine.transcribe(file: frenchURL, language: DictationLanguage(id: "fr"))
        print("Nemotron heard French:", frenchText)
        #expect(frenchText.lowercased().contains("table"))
    }

    @Test func parakeetUltraShowsWordsWhileSpeaking() async throws {
        guard Self.isOn("parakeet") else { return }
        let engine = ParakeetEngine(model: .parakeet, version: .ultra, root: Self.modelsDirectory.appendingPathComponent("parakeet"))
        if await !engine.isDownloaded {
            try await timed("Parakeet Ultra download") { try await engine.download { _ in } }
        }
        let url = try SpokenSample.make(Self.english + " " + Self.english)
        let (session, feeding) = try RereadingDictationSession.start(read: { samples in
            try await engine.transcribe(samples)
        }, file: url)
        let started = Date()
        let collector = Task {
            var first: TimeInterval?
            var seen: [String] = []
            for await update in session.updates {
                if case .transcript(let live) = update, !live.isEmpty {
                    if first == nil { first = Date().timeIntervalSince(started) }
                    seen.append(live.text)
                }
            }
            return (first, seen)
        }
        await feeding.value
        let text = try await session.finish()
        let (first, seen) = await collector.value
        print("Parakeet Ultra heard:", text)
        print("Parakeet Ultra first words after \(first.map { String(format: "%.2f", $0) } ?? "never") s; live:", seen)
        #expect(text.lowercased().contains("friday"))
        #expect((first ?? 99) < 3)
    }

    @Test func whisperHearsEnglishAndShowsWordsOnTheWay() async throws {
        guard Self.isOn("whisper") else { return }
        let engine = WhisperEngine(model: .whisper, root: Self.modelsDirectory.appendingPathComponent("whisper"))
        if await !engine.isDownloaded {
            try await timed("Whisper download") { try await engine.download { _ in } }
        }
        let url = try SpokenSample.make(Self.english)
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
        print("Whisper heard:", text, "live:", await collector.value)
        #expect(text.lowercased().contains("report"))
        #expect(text.lowercased().contains("friday"))
    }

    @Test func whisperGivesNoWordsForSilence() async throws {
        guard Self.isOn("whisper") else { return }
        let engine = WhisperEngine(model: .whisper, root: Self.modelsDirectory.appendingPathComponent("whisper"))
        guard await engine.isDownloaded else { return }
        let url = try SpokenSample.make("[[slnc 3000]]")
        let (session, feeding) = try await WhisperDictationSession.start(engine: engine, language: .automatic, file: url)
        await feeding.value
        let text = try await session.finish()
        #expect(text.isEmpty)
    }

    /// The models that read again: each must download, load and write the sentence, with its first words soon.
    @Test(arguments: [DictationModel.parakeetEnglishV2, .parakeetSmall, .whisperSmall, .whisperLarge])
    func eachAccurateModelHearsTheSentence(model: DictationModel) async throws {
        guard Self.isOn(model.rawValue) else { return }
        let macOS = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard macOS >= model.minimumMacOS else { return }
        let service = SpeechService(modelsDirectory: Self.modelsDirectory)
        if await service.status(of: model, language: .automatic) != .ready {
            try await timed("\(model.displayName) download") {
                try await service.download(model, language: .automatic) { _ in }
            }
        }
        let url = try SpokenSample.make(Self.english)
        let samples = try SpeechAudio.samples(ofFile: url)
        let language = await service.defaultLanguage(for: model)
        let text = try await timed("\(model.displayName) reading") {
            try await Self.read(samples, with: model, language: language, in: service)
        }
        print("\(model.displayName) heard:", text)
        #expect(text.lowercased().contains("report"))
        #expect(text.lowercased().contains("friday"))
    }

    /// Reads a whole recording through the engine behind `model`, as each reading during a dictation does.
    static func read(_ samples: [Float], with model: DictationModel, language: DictationLanguage, in service: SpeechService) async throws -> String {
        let root = modelsDirectory
        switch model {
        case .parakeetEnglishV2:
            return try await ParakeetEngine(model: model, version: .v2, root: root.appendingPathComponent("parakeet-tdt-v2")).transcribe(samples)
        case .parakeetSmall:
            return try await ParakeetEngine(model: model, version: .redux, root: root.appendingPathComponent("parakeet-redux")).transcribe(samples)
        case .whisperSmall:
            return try await WhisperEngine(model: model, root: root.appendingPathComponent("whisper-small"))
                .transcribe(samples, language: language).map(\.text).joined(separator: " ")
        case .whisperLarge:
            return try await WhisperEngine(model: model, root: root.appendingPathComponent("whisper-large-v3"))
                .transcribe(samples, language: language).map(\.text).joined(separator: " ")
        default:
            return ""
        }
    }

    @Test func unloadingFreesTheModelAndItLoadsAgain() async throws {
        guard Self.isOn("parakeet") else { return }
        let engine = ParakeetEngine(model: .parakeet, version: .ultra, root: Self.modelsDirectory.appendingPathComponent("parakeet"))
        guard await engine.isDownloaded else { return }
        let url = try SpokenSample.make(Self.english)
        let samples = try SpeechAudio.samples(ofFile: url)
        _ = try await engine.transcribe(samples)
        await engine.unload()
        let text = try await timed("Parakeet Ultra load after unloading") { try await engine.transcribe(samples) }
        #expect(text.lowercased().contains("friday"))
    }
}

/// How long a model takes to load, the first time in a process and again after unloading. Off unless
/// OMAN_LOAD_TIMES points at a folder of downloaded models; it only reads them.
@Suite(.serialized) struct ModelLoadTimeTests {
    @Test func loadTimes() async throws {
        guard let path = ProcessInfo.processInfo.environment["OMAN_LOAD_TIMES"] else { return }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let engine = StreamingEngine(kind: .parakeetEnglish, root: root.appendingPathComponent("parakeet-unified-en"))
        guard await engine.isDownloaded else { return }
        var started = Date()
        await engine.prepare(language: DictationLanguage(id: "en"))
        print("LOAD Parakeet Unified, first in this process: \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
        await engine.unload()
        started = Date()
        await engine.prepare(language: DictationLanguage(id: "en"))
        print("LOAD Parakeet Unified, after unloading: \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
        started = Date()
        await engine.prepare(language: DictationLanguage(id: "en"))
        print("LOAD Parakeet Unified, already loaded: \(String(format: "%.3f", Date().timeIntervalSince(started))) s")
    }
}
