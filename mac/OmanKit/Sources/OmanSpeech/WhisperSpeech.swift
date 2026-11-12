import AVFoundation
import Foundation
import OmanCore
@preconcurrency import WhisperKit

/// OpenAI's Whisper large-v3 turbo, in Argmax's compressed build for the Neural Engine, run by WhisperKit. It knows
/// about a hundred languages, and can be told one or work it out.
actor WhisperEngine {
    static let variant = "openai_whisper-large-v3-v20240930_626MB"
    static let repository = "argmaxinc/whisperkit-coreml"
    /// Measured from the files WhisperKit downloads, with the tokenizer.
    static let downloadSize: Int64 = 629_000_000

    static let languages: [DictationLanguage] = Set(Constants.languages.values)
        .map(DictationLanguage.init(id:))
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

    private let root: URL
    private var whisper: WhisperKit?
    /// The person's own words, given to Whisper as text it has just heard, so it expects them.
    private var promptTokens: [Int]?

    init(root: URL) {
        self.root = root
    }

    /// WhisperKit keeps Hugging Face's layout under the folder it is given.
    private var modelFolder: URL {
        root.appendingPathComponent("models/\(Self.repository)/\(Self.variant)", isDirectory: true)
    }

    /// Written once the model and its tokenizer are both in place and have loaded, so a download that stopped
    /// half way never counts as one.
    private var readyMarker: URL { root.appendingPathComponent("ready") }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: readyMarker.path)
            && FileManager.default.fileExists(atPath: modelFolder.path)
    }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try await WhisperKit.download(variant: Self.variant, downloadBase: root, from: Self.repository) { update in
            progress(update.fractionCompleted * 0.9)
        }
        try Task.checkCancellation()
        // Loading once fetches the tokenizer into the same folder and prepares the model for the Neural Engine,
        // so the first dictation needs no network and starts at once.
        _ = try await loaded()
        try Data().write(to: readyMarker)
        progress(1)
    }

    func remove() async throws {
        await unload()
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func unload() async {
        await whisper?.unloadModels()
        whisper = nil
    }

    func startSession(language: DictationLanguage, words: [String]) async throws -> any DictationSession {
        guard isDownloaded else { throw DictationError.modelNotReady(.whisper) }
        return try WhisperDictationSession.start(engine: self, language: language, needsLoading: whisper == nil) {
            let whisper = try await self.loaded()
            await self.setPrompt(words.isEmpty ? nil : whisper.tokenizer?.encode(text: " " + words.joined(separator: ", ")))
        }
    }

    private func setPrompt(_ tokens: [Int]?) {
        promptTokens = tokens
    }

    /// Loads the model ahead of a dictation.
    func prepare() async {
        guard isDownloaded else { return }
        _ = try? await loaded()
    }

    /// The text of each stretch of speech Whisper finds, with where it starts and ends in seconds.
    func transcribe(_ samples: [Float], language: DictationLanguage) async throws -> [WhisperSegment] {
        let whisper = try await loaded()
        let results = try await whisper.transcribe(
            audioArray: samples,
            decodeOptions: Self.options(for: language, prompt: promptTokens)
        )
        return results.flatMap(\.segments).compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !WhisperSegment.isNoise(text) else { return nil }
            return WhisperSegment(text: text, start: Double(segment.start), end: Double(segment.end))
        }
    }

    private func loaded() async throws -> WhisperKit {
        if let whisper { return whisper }
        let config = WhisperKitConfig(
            downloadBase: root,
            modelFolder: modelFolder.path,
            tokenizerFolder: root,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        let loaded = try await WhisperKit(config)
        whisper = loaded
        return loaded
    }

    static func options(for language: DictationLanguage, prompt: [Int]? = nil) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language.isAutomatic ? nil : language.id,
            temperature: 0,
            usePrefillPrompt: !language.isAutomatic,
            detectLanguage: language.isAutomatic,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            promptTokens: prompt,
            suppressBlank: true,
            noSpeechThreshold: 0.6,
            chunkingStrategy: .vad
        )
    }
}

struct WhisperSegment: Equatable, Sendable {
    let text: String
    let start: Double
    let end: Double

    /// Whisper writes what it hears of silence or noise in brackets, such as "[Music]" or "(silence)".
    static func isNoise(_ text: String) -> Bool {
        let bracketed = (text.hasPrefix("[") && text.hasSuffix("]")) || (text.hasPrefix("(") && text.hasSuffix(")"))
        return bracketed || text.allSatisfy { !$0.isLetter && !$0.isNumber }
    }
}

/// One dictation through Whisper. Whisper reads a stretch of sound at a time, so every second the words not yet
/// settled are read again with the new sound; all but the last two stretches then count as settled.
final class WhisperDictationSession: DictationSession, @unchecked Sendable {
    /// Sound quieter than this, as a root mean square, is taken for silence, which Whisper tends to fill with
    /// made-up words.
    static let silence: Float = 0.006
    static let readInterval = Duration.milliseconds(250)

    let updates: AsyncStream<DictationUpdate>
    private let updatesContinuation: AsyncStream<DictationUpdate>.Continuation
    private let engine: WhisperEngine
    private let language: DictationLanguage
    private var capture: MicrophoneCapture?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var settled = ""
    private var settledSamples = 0
    private var readSamples = 0
    private var loadError: (any Error)?
    private var readTask: Task<Void, Never>?

    private init(engine: WhisperEngine, language: DictationLanguage) {
        self.engine = engine
        self.language = language
        (updates, updatesContinuation) = AsyncStream.makeStream(of: DictationUpdate.self)
    }

    /// The microphone starts at once, and the model loads meanwhile, so nothing said while it loads is lost.
    static func start(
        engine: WhisperEngine,
        language: DictationLanguage,
        needsLoading: Bool = false,
        load: @escaping @Sendable () async throws -> Void = {}
    ) throws -> WhisperDictationSession {
        let session = WhisperDictationSession(engine: engine, language: language)
        let capture = MicrophoneCapture(
            targetFormat: SpeechAudio.format16k,
            onAudio: { [weak session] buffer in session?.append(SpeechAudio.samples(of: buffer)) },
            onLevel: { [weak session] level in session?.updatesContinuation.yield(.level(level)) }
        )
        session.capture = capture
        try capture.start()
        if needsLoading {
            session.updatesContinuation.yield(.loadingModel(true))
        }
        session.readTask = Task { [weak session] in
            do {
                try await load()
            } catch {
                session?.lock.withLock { session?.loadError = error }
            }
            if needsLoading {
                session?.updatesContinuation.yield(.loadingModel(false))
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: readInterval)
                guard !Task.isCancelled, let session else { return }
                await session.readNewSound()
            }
        }
        return session
    }

    /// For the tests: plays a recording in, a tenth of a second at a time, as the microphone would.
    static func start(engine: WhisperEngine, language: DictationLanguage, file url: URL) async throws
        -> (session: WhisperDictationSession, feeding: Task<Void, Never>) {
        let session = WhisperDictationSession(engine: engine, language: language)
        let all = try SpeechAudio.samples(ofFile: url)
        let feeding = Task {
            let step = Int(SpeechAudio.sampleRate / 10)
            for start in stride(from: 0, to: all.count, by: step) {
                session.append(Array(all[start..<min(start + step, all.count)]))
                try? await Task.sleep(for: .milliseconds(100))
                await session.readNewSound()
            }
        }
        return (session, feeding)
    }

    private func append(_ chunk: [Float]) {
        lock.withLock { samples.append(contentsOf: chunk) }
    }

    private func readNewSound() async {
        let (window, offset, total, fresh) = lock.withLock {
            (Array(samples[settledSamples...]), settledSamples, samples.count, samples[readSamples...])
        }
        guard total - readSamples >= Int(SpeechAudio.sampleRate) else { return }
        lock.withLock { readSamples = total }
        // Silence after nothing said is skipped, so Whisper doesn't invent words for it.
        let hasWords = lock.withLock { !settled.isEmpty }
        guard hasWords || SpeechAudio.energy(of: fresh) > Self.silence else { return }
        guard let segments = try? await engine.transcribe(window, language: language) else { return }

        var tentative = segments.map(\.text).joined(separator: " ")
        let live = lock.withLock {
            if segments.count > 2, let last = segments.dropLast(2).last {
                settled = LiveTranscript.join(settled, segments.dropLast(2).map(\.text).joined(separator: " "))
                settledSamples = min(offset + Int(last.end * SpeechAudio.sampleRate), samples.count)
                tentative = segments.suffix(2).map(\.text).joined(separator: " ")
            }
            return LiveTranscript(confirmed: settled, tentative: tentative)
        }
        updatesContinuation.yield(.transcript(live))
    }

    func finish() async throws -> String {
        capture?.stop()
        readTask?.cancel()
        await readTask?.value
        if let loadError = lock.withLock({ self.loadError }) {
            updatesContinuation.finish()
            throw loadError
        }
        let (window, quietSoFar) = lock.withLock {
            (Array(samples[settledSamples...]), settled.isEmpty)
        }
        var rest = ""
        if !window.isEmpty, !(quietSoFar && SpeechAudio.energy(of: window[...]) <= Self.silence) {
            rest = try await engine.transcribe(window, language: language).map(\.text).joined(separator: " ")
        }
        updatesContinuation.finish()
        return lock.withLock { LiveTranscript.join(settled, rest) }
    }

    func cancel() async {
        capture?.stop()
        readTask?.cancel()
        updatesContinuation.finish()
    }
}
