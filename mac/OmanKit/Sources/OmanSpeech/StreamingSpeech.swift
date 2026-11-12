import AVFoundation
import FluidAudio
import Foundation
import OmanCore

/// NVIDIA's Unified models, run by FluidAudio, which stream: each second or less of new sound is decoded as it
/// comes, so words appear while they are said. Parakeet Unified knows English; Nemotron Unified knows 25 European
/// languages and is told which one, or works it out.
actor StreamingEngine {
    enum Kind: Sendable {
        case parakeetEnglish
        case nemotron
    }

    private let kind: Kind
    private let root: URL
    private var manager: StreamingUnifiedAsrManager?
    private var loadedLanguage: DictationLanguage?

    init(kind: Kind, root: URL) {
        self.kind = kind
        self.root = root
    }

    /// The languages Nemotron can be told, as ISO codes.
    static let nemotronLanguages: [String] = NemotronUnifiedLanguage.allCases
        .filter { $0 != .auto }
        .map(\.rawValue)

    private var readyMarker: URL { root.appendingPathComponent("ready") }

    var isDownloaded: Bool { FileManager.default.fileExists(atPath: readyMarker.path) }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = StreamingUnifiedAsrManager(config: Self.config(kind, language: .automatic))
        // Downloads what is missing, then loads it once, which prepares it for the Neural Engine.
        try await manager.loadModels(to: root) { update in
            progress(update.fractionCompleted * 0.97)
        }
        try Task.checkCancellation()
        try Data().write(to: readyMarker)
        self.manager = manager
        loadedLanguage = .automatic
        progress(1)
    }

    func remove() async throws {
        await unload()
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
        loadedLanguage = nil
    }

    func startSession(language: DictationLanguage) async throws -> any DictationSession {
        guard isDownloaded else {
            throw DictationError.modelNotReady(kind == .parakeetEnglish ? .parakeetEnglish : .nemotron)
        }
        return try StreamingDictationSession.start(needsLoading: !isLoaded(language: language)) {
            try await self.loaded(language: language)
        }
    }

    /// Loads the model ahead of a dictation.
    func prepare(language: DictationLanguage) async {
        guard isDownloaded else { return }
        _ = try? await loaded(language: language)
    }

    private func isLoaded(language: DictationLanguage) -> Bool {
        manager != nil && (kind == .parakeetEnglish || loadedLanguage == language)
    }

    /// Plays a recording into the same live path the microphone uses, for the tests. Returns the live words seen
    /// on the way, the final text and how long the first words took.
    func transcribe(file url: URL, language: DictationLanguage) async throws
        -> (live: [String], text: String, firstWordsAfter: TimeInterval?) {
        let manager = try await loaded(language: language)
        try await manager.reset()
        let started = Date()
        let seen = Seen()
        await manager.setPartialTranscriptCallback { text in seen.add(text, at: Date().timeIntervalSince(started)) }
        let samples = try SpeechAudio.samples(ofFile: url)
        let step = Int(SpeechAudio.sampleRate / 10)
        for start in stride(from: 0, to: samples.count, by: step) {
            guard let buffer = SpeechAudio.buffer(from: Array(samples[start..<min(start + step, samples.count)])) else {
                continue
            }
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
            // As fast as a microphone would give it.
            try await Task.sleep(for: .milliseconds(100))
        }
        let text = try await manager.finish()
        return (seen.texts, text, seen.firstAt)
    }

    private func loaded(language: DictationLanguage) async throws -> StreamingUnifiedAsrManager {
        // Nemotron takes its language when it loads, so another language needs it loaded again.
        if let manager, isLoaded(language: language) {
            return manager
        }
        await manager?.cleanup()
        let manager = StreamingUnifiedAsrManager(config: Self.config(kind, language: language))
        try await manager.loadModels(to: root)
        self.manager = manager
        loadedLanguage = language
        return manager
    }

    /// Parakeet answers 0.64 seconds behind the voice, its tier with the best accuracy for the work it takes.
    /// Nemotron's nearest tier answers 1.12 seconds behind, and is its most accurate.
    static func config(_ kind: Kind, language: DictationLanguage) -> UnifiedConfig {
        switch kind {
        case .parakeetEnglish:
            return UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 1)
        case .nemotron:
            let spoken = NemotronUnifiedLanguage(rawValue: language.id) ?? .auto
            return UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 7, family: .nemotronMultilingual(spoken))
        }
    }

    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        private var first: TimeInterval?

        var texts: [String] { lock.withLock { stored } }
        var firstAt: TimeInterval? { lock.withLock { first } }

        func add(_ text: String, at seconds: TimeInterval) {
            lock.withLock {
                stored.append(text)
                if first == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty { first = seconds }
            }
        }
    }
}

/// One dictation through a streaming model: the microphone's sound goes in as it comes, and each newly decoded
/// stretch extends the words. Nothing already shown changes, so every word is settled. The microphone starts at
/// once; while the model loads, its sound waits, and is decoded as soon as the model is ready.
final class StreamingDictationSession: DictationSession, @unchecked Sendable {
    let updates: AsyncStream<DictationUpdate>
    private let updatesContinuation: AsyncStream<DictationUpdate>.Continuation
    private let samplesContinuation: AsyncStream<[Float]>.Continuation
    private let lock = NSLock()
    private var manager: StreamingUnifiedAsrManager?
    private var loadError: (any Error)?
    private var feedTask: Task<Void, Never>?
    private var capture: MicrophoneCapture?

    private init(
        samplesContinuation: AsyncStream<[Float]>.Continuation,
        updates: AsyncStream<DictationUpdate>,
        updatesContinuation: AsyncStream<DictationUpdate>.Continuation
    ) {
        self.samplesContinuation = samplesContinuation
        self.updates = updates
        self.updatesContinuation = updatesContinuation
    }

    static func start(
        needsLoading: Bool,
        load: @escaping @Sendable () async throws -> StreamingUnifiedAsrManager
    ) throws -> StreamingDictationSession {
        let (updates, updatesContinuation) = AsyncStream.makeStream(of: DictationUpdate.self)
        let (samples, samplesContinuation) = AsyncStream.makeStream(of: [Float].self)
        let session = StreamingDictationSession(
            samplesContinuation: samplesContinuation,
            updates: updates,
            updatesContinuation: updatesContinuation
        )
        if needsLoading {
            updatesContinuation.yield(.loadingModel(true))
        }
        session.feedTask = Task {
            let manager: StreamingUnifiedAsrManager
            do {
                manager = try await load()
                try await manager.reset()
            } catch {
                session.lock.withLock { session.loadError = error }
                updatesContinuation.yield(.loadingModel(false))
                return
            }
            await manager.setPartialTranscriptCallback { text in
                updatesContinuation.yield(.transcript(LiveTranscript(confirmed: text)))
            }
            session.lock.withLock { session.manager = manager }
            if needsLoading {
                updatesContinuation.yield(.loadingModel(false))
            }
            // One buffer after another, in order, starting with any that waited for the model.
            for await chunk in samples {
                guard let buffer = SpeechAudio.buffer(from: chunk) else { continue }
                do {
                    try await manager.appendAudio(buffer)
                    try await manager.processBufferedAudio()
                } catch {
                    return
                }
            }
        }
        let capture = MicrophoneCapture(
            targetFormat: SpeechAudio.format16k,
            onAudio: { buffer in samplesContinuation.yield(SpeechAudio.samples(of: buffer)) },
            onLevel: { level in updatesContinuation.yield(.level(level)) }
        )
        session.capture = capture
        do {
            try capture.start()
        } catch {
            session.feedTask?.cancel()
            samplesContinuation.finish()
            updatesContinuation.finish()
            throw error
        }
        return session
    }

    func finish() async throws -> String {
        capture?.stop()
        samplesContinuation.finish()
        await feedTask?.value
        defer { updatesContinuation.finish() }
        let (manager, loadError) = lock.withLock { (self.manager, self.loadError) }
        if let loadError { throw loadError }
        guard let manager else { return "" }
        return try await manager.finish()
    }

    func cancel() async {
        capture?.stop()
        samplesContinuation.finish()
        feedTask?.cancel()
        await feedTask?.value
        if let manager = lock.withLock({ self.manager }) {
            try? await manager.reset()
        }
        updatesContinuation.finish()
    }
}
