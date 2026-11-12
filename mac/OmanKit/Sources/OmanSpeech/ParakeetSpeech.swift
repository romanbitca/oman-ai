@preconcurrency import CoreML
import FluidAudio
import Foundation
import OmanCore

/// Moondream's Parakeet Ultra, a post-training of NVIDIA's Parakeet TDT v3, run by FluidAudio. It knows 25 European
/// languages and works out which one is spoken; it can't be told which. It reads a whole recording at once, more
/// than a hundred times faster than it was spoken, so while the person speaks it reads everything again every
/// second to show the words so far.
actor ParakeetEngine {
    static let version: AsrModelVersion = .ultra
    /// What the model writes, as ISO codes.
    static let languageCodes = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it",
        "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk",
    ]

    private let root: URL
    private var manager: AsrManager?

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
        _ = try await loaded()
        progress(1)
    }

    func remove() async throws {
        await unload()
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func unload() async {
        manager = nil
    }

    func startSession() async throws -> any DictationSession {
        guard isDownloaded else { throw DictationError.modelNotReady(.parakeet) }
        _ = try await loaded()
        return try RereadingDictationSession.start { samples in
            try await self.transcribe(samples)
        }
    }

    /// The text of a whole recording.
    func transcribe(_ samples: [Float]) async throws -> String {
        let manager = try await loaded()
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(samples, decoderState: &state).text
    }

    private func loaded() async throws -> AsrManager {
        if let manager { return manager }
        let models = try await AsrModels.load(from: directory, version: Self.version)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        return manager
    }
}

/// One dictation through a model that reads a whole recording at once: everything said so far is read again
/// every second while the person speaks, and once more at the end. The last words of each reading are shown as a
/// guess, since the next reading may change them.
final class RereadingDictationSession: DictationSession, @unchecked Sendable {
    static let readInterval = Duration.milliseconds(900)
    /// Readings of a long dictation come less often, since each one reads more.
    static let longDictation = 45 * Int(SpeechAudio.sampleRate)
    /// Quieter than this, as a root mean square, counts as silence, so nothing is read before anything is said.
    static let silence: Float = 0.006

    let updates: AsyncStream<DictationUpdate>
    private let updatesContinuation: AsyncStream<DictationUpdate>.Continuation
    private let read: @Sendable ([Float]) async throws -> String
    private var capture: MicrophoneCapture?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var readSamples = 0
    private var heardSpeech = false
    private var readTask: Task<Void, Never>?

    private init(read: @escaping @Sendable ([Float]) async throws -> String) {
        self.read = read
        (updates, updatesContinuation) = AsyncStream.makeStream(of: DictationUpdate.self)
    }

    static func start(read: @escaping @Sendable ([Float]) async throws -> String) throws -> RereadingDictationSession {
        let session = RereadingDictationSession(read: read)
        let capture = MicrophoneCapture(
            targetFormat: SpeechAudio.format16k,
            onAudio: { [weak session] buffer in session?.append(SpeechAudio.samples(of: buffer)) },
            onLevel: { [weak session] level in session?.updatesContinuation.yield(.level(level)) }
        )
        session.capture = capture
        try capture.start()
        session.readTask = Task { [weak session] in
            while !Task.isCancelled {
                try? await Task.sleep(for: readInterval)
                guard !Task.isCancelled, let session else { return }
                await session.readAgain()
            }
        }
        return session
    }

    /// For the tests: plays a recording in, a tenth of a second at a time, as the microphone would, reading again
    /// as it goes.
    static func start(read: @escaping @Sendable ([Float]) async throws -> String, file url: URL) throws
        -> (session: RereadingDictationSession, feeding: Task<Void, Never>) {
        let session = RereadingDictationSession(read: read)
        let all = try SpeechAudio.samples(ofFile: url)
        let feeding = Task {
            let step = Int(SpeechAudio.sampleRate / 10)
            var sinceRead = 0
            for start in stride(from: 0, to: all.count, by: step) {
                session.append(Array(all[start..<min(start + step, all.count)]))
                try? await Task.sleep(for: .milliseconds(100))
                sinceRead += 100
                if sinceRead >= 900 {
                    sinceRead = 0
                    await session.readAgain()
                }
            }
        }
        return (session, feeding)
    }

    private func append(_ chunk: [Float]) {
        lock.withLock {
            samples.append(contentsOf: chunk)
            if !heardSpeech, SpeechAudio.energy(of: chunk[...]) > Self.silence {
                heardSpeech = true
            }
        }
    }

    private func readAgain() async {
        let (all, fresh, speech) = lock.withLock { (samples, samples.count - readSamples, heardSpeech) }
        let needed = all.count > Self.longDictation ? Int(SpeechAudio.sampleRate) * 2 : Int(SpeechAudio.sampleRate) / 2
        guard speech, fresh >= needed else { return }
        lock.withLock { readSamples = all.count }
        guard let text = try? await read(all), !Task.isCancelled else { return }
        updatesContinuation.yield(.transcript(Self.split(text)))
    }

    /// The last three words as the guess, the rest as settled.
    static func split(_ text: String) -> LiveTranscript {
        let words = text.split(separator: " ")
        let settledCount = max(words.count - 3, 0)
        return LiveTranscript(
            confirmed: words[..<settledCount].joined(separator: " "),
            tentative: words[settledCount...].joined(separator: " ")
        )
    }

    func finish() async throws -> String {
        capture?.stop()
        readTask?.cancel()
        await readTask?.value
        let (all, speech) = lock.withLock { (samples, heardSpeech) }
        updatesContinuation.finish()
        guard speech, !all.isEmpty else { return "" }
        return try await read(all)
    }

    func cancel() async {
        capture?.stop()
        readTask?.cancel()
        updatesContinuation.finish()
    }
}
