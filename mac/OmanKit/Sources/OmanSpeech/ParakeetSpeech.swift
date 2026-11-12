import AVFoundation
import FluidAudio
import Foundation
import OmanCore

/// NVIDIA's Parakeet in Moondream's improved Ultra version, run by FluidAudio. It knows 25 European languages and
/// works out which one is spoken; it can't be told which.
actor ParakeetEngine {
    static let version: AsrModelVersion = .ultra
    /// Measured from the files FluidAudio downloads.
    static let downloadSize: Int64 = 632_000_000
    /// What the model writes, as ISO codes, for the explanation in Settings.
    static let languageCodes = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it",
        "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk",
    ]

    private let root: URL
    private var models: AsrModels?

    init(root: URL) {
        self.root = root
    }

    /// FluidAudio keeps the model in a folder of its own beside this one, so `root` holds everything.
    private var directory: URL { root.appendingPathComponent("models", isDirectory: true) }

    var isDownloaded: Bool { AsrModels.modelsExist(at: directory, version: Self.version) }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try await AsrModels.download(to: directory, version: Self.version) { update in
            progress(update.fractionCompleted * 0.9)
        }
        try Task.checkCancellation()
        // Loading once here prepares the model for the Neural Engine, which takes a while the first time,
        // so the first dictation starts at once.
        _ = try await loadedModels()
        progress(1)
    }

    func remove() throws {
        models = nil
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func startSession() async throws -> any DictationSession {
        guard isDownloaded else { throw DictationError.modelNotReady(.parakeet) }
        return try await ParakeetDictationSession.start(models: try await loadedModels())
    }

    /// Plays a recording into the same live path the microphone uses, for the tests that check the model without
    /// one. Returns the live words seen on the way and the final text.
    func transcribe(file url: URL) async throws -> (live: [LiveTranscript], text: String) {
        let samples = try SpeechAudio.samples(ofFile: url)
        let manager = SlidingWindowAsrManager(config: .streaming)
        try await manager.loadModels(try await loadedModels())
        let transcriptions = await manager.transcriptionUpdates
        try await manager.startStreaming(source: .system)
        let collector = Task {
            var seen: [LiveTranscript] = []
            for await update in transcriptions {
                seen.append(LiveTranscript(confirmed: update.confirmedTranscript, tentative: update.volatileTranscript))
            }
            return seen
        }
        let step = Int(SpeechAudio.sampleRate / 10)
        for start in stride(from: 0, to: samples.count, by: step) {
            guard let buffer = SpeechAudio.buffer(from: Array(samples[start..<min(start + step, samples.count)])) else {
                continue
            }
            await manager.streamAudio(buffer)
        }
        let text = try await manager.finish()
        await manager.cancel()
        return (await collector.value, text)
    }

    private func loadedModels() async throws -> AsrModels {
        if let models { return models }
        let loaded = try await AsrModels.load(from: directory, version: Self.version)
        models = loaded
        return loaded
    }
}

/// One dictation through Parakeet. FluidAudio decodes the last seconds again every second, so the newest words
/// are a guess that settles as more is heard.
final class ParakeetDictationSession: DictationSession, @unchecked Sendable {
    let updates: AsyncStream<DictationUpdate>
    private let updatesContinuation: AsyncStream<DictationUpdate>.Continuation
    private let manager: SlidingWindowAsrManager
    private let capture: MicrophoneCapture
    private let samplesContinuation: AsyncStream<[Float]>.Continuation
    private let feedTask: Task<Void, Never>
    private let resultsTask: Task<Void, Never>

    private init(
        manager: SlidingWindowAsrManager,
        capture: MicrophoneCapture,
        samplesContinuation: AsyncStream<[Float]>.Continuation,
        feedTask: Task<Void, Never>,
        resultsTask: Task<Void, Never>,
        updates: AsyncStream<DictationUpdate>,
        updatesContinuation: AsyncStream<DictationUpdate>.Continuation
    ) {
        self.manager = manager
        self.capture = capture
        self.samplesContinuation = samplesContinuation
        self.feedTask = feedTask
        self.resultsTask = resultsTask
        self.updates = updates
        self.updatesContinuation = updatesContinuation
    }

    static func start(models: AsrModels) async throws -> ParakeetDictationSession {
        let manager = SlidingWindowAsrManager(config: .streaming)
        try await manager.loadModels(models)
        // Subscribed before any sound goes in, as FluidAudio asks.
        let transcriptions = await manager.transcriptionUpdates
        try await manager.startStreaming(source: .microphone)

        let (updates, updatesContinuation) = AsyncStream.makeStream(of: DictationUpdate.self)
        let resultsTask = Task {
            for await update in transcriptions {
                updatesContinuation.yield(.transcript(LiveTranscript(
                    confirmed: update.confirmedTranscript,
                    tentative: update.volatileTranscript
                )))
            }
        }

        let (samples, samplesContinuation) = AsyncStream.makeStream(of: [Float].self)
        // In order, one buffer after another, which separate tasks per buffer would not keep.
        let feedTask = Task {
            for await chunk in samples {
                guard let buffer = SpeechAudio.buffer(from: chunk) else { continue }
                await manager.streamAudio(buffer)
            }
        }
        let capture = MicrophoneCapture(
            targetFormat: SpeechAudio.format16k,
            onAudio: { buffer in samplesContinuation.yield(SpeechAudio.samples(of: buffer)) },
            onLevel: { level in updatesContinuation.yield(.level(level)) }
        )
        let session = ParakeetDictationSession(
            manager: manager,
            capture: capture,
            samplesContinuation: samplesContinuation,
            feedTask: feedTask,
            resultsTask: resultsTask,
            updates: updates,
            updatesContinuation: updatesContinuation
        )
        do {
            try capture.start()
        } catch {
            await session.cancel()
            throw error
        }
        return session
    }

    func finish() async throws -> String {
        capture.stop()
        samplesContinuation.finish()
        await feedTask.value
        let text = try await manager.finish()
        resultsTask.cancel()
        updatesContinuation.finish()
        return text
    }

    func cancel() async {
        capture.stop()
        samplesContinuation.finish()
        feedTask.cancel()
        await manager.cancel()
        resultsTask.cancel()
        updatesContinuation.finish()
    }
}

/// Sound as the downloaded models take it: 16,000 samples a second, one channel, as floating point numbers.
enum SpeechAudio {
    static let sampleRate = 16_000.0

    // A format this plain always exists; the force unwrap can't fail.
    nonisolated(unsafe) static let format16k = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    static func samples(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    static func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format16k, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// A recording's sound in the models' format.
    static func samples(ofFile url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: source)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format16k),
              let converted = MicrophoneCapture.convert(source, with: converter, to: format16k)
        else { return [] }
        return samples(of: converted)
    }

    /// How loud a stretch of sound is, as its root mean square.
    static func energy(of samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return (sum / Float(samples.count)).squareRoot()
    }
}
