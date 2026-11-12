import FluidAudio
import Foundation
import OmanCore

/// Dictation's speech models: Apple's, part of macOS 26 and later, and the ones downloaded once from Settings.
/// Each runs on the Mac, so the sound never leaves it. A downloaded model stays loaded after a dictation, so the
/// next one starts at once, until `unloadModels(after:)` frees it.
public actor SpeechService: SpeechRecognizing {
    private let parakeetEnglish: StreamingEngine
    private let nemotron: StreamingEngine
    private let parakeets: [DictationModel: ParakeetEngine]
    private let whispers: [DictationModel: WhisperEngine]
    private let canary: CanaryEngine
    private var unloadTask: Task<Void, Never>?

    /// `modelsDirectory` holds the downloaded models, one folder each, so removing one deletes its folder.
    public init(modelsDirectory: URL = SpeechService.defaultModelsDirectory) {
        func folder(_ name: String) -> URL { modelsDirectory.appendingPathComponent(name, isDirectory: true) }
        parakeetEnglish = StreamingEngine(kind: .parakeetEnglish, root: folder("parakeet-unified-en"))
        nemotron = StreamingEngine(kind: .nemotron, root: folder("nemotron-unified"))
        parakeets = [
            .parakeet: ParakeetEngine(model: .parakeet, version: .ultra, root: folder("parakeet")),
            .parakeetEnglishV2: ParakeetEngine(model: .parakeetEnglishV2, version: .v2, root: folder("parakeet-tdt-v2")),
            .parakeetSmall: ParakeetEngine(model: .parakeetSmall, version: .redux, root: folder("parakeet-redux")),
        ]
        whispers = [
            .whisper: WhisperEngine(model: .whisper, root: folder("whisper")),
            .whisperLarge: WhisperEngine(model: .whisperLarge, root: folder("whisper-large-v3")),
            .whisperSmall: WhisperEngine(model: .whisperSmall, root: folder("whisper-small")),
        ]
        canary = CanaryEngine(root: folder("canary"))
    }

    /// Beside the database, in Application Support.
    public static var defaultModelsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("oman/SpeechModels", isDirectory: true)
    }

    public func status(of model: DictationModel, language: DictationLanguage) async -> DictationModelStatus {
        let macOS = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard macOS >= model.minimumMacOS else {
            return .unavailable("\(model.displayName) needs macOS \(model.minimumMacOS) or later.")
        }
        let downloaded: Bool
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else {
                return .unavailable("Apple's speech model needs macOS 26 or later.")
            }
            return await AppleSpeech.status(of: language)
        case .parakeetEnglish: downloaded = await parakeetEnglish.isDownloaded
        case .nemotron: downloaded = await nemotron.isDownloaded
        case .canary: downloaded = await canary.isDownloaded
        case .parakeet, .parakeetEnglishV2, .parakeetSmall: downloaded = await parakeets[model]?.isDownloaded ?? false
        case .whisper, .whisperLarge, .whisperSmall: downloaded = await whispers[model]?.isDownloaded ?? false
        }
        return downloaded ? .ready : .needsDownload(bytes: model.downloadSize)
    }

    public func languages(for model: DictationModel) async -> [DictationLanguage] {
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else { return [] }
            return await AppleSpeech.languages()
        case .parakeetEnglish, .parakeetEnglishV2:
            return [DictationLanguage(id: "en")]
        case .nemotron:
            return [.automatic] + Self.sorted(StreamingEngine.nemotronLanguages)
        case .canary:
            return Self.sorted(CanaryEngine.languageCodes)
        case .parakeet, .parakeetSmall:
            // Parakeet can't be told the language, so the only choice is to let it work it out.
            return [.automatic]
        case .whisper, .whisperLarge, .whisperSmall:
            return [.automatic] + WhisperEngine.languages
        }
    }

    public func spokenLanguages(of model: DictationModel) async -> [String] {
        switch model {
        case .parakeet, .parakeetSmall: ParakeetEngine.europeanLanguages
        case .nemotron: StreamingEngine.nemotronLanguages
        case .canary: CanaryEngine.languageCodes
        default: await languages(for: model).filter { !$0.isAutomatic }.map(\.id)
        }
    }

    public func defaultLanguage(for model: DictationModel) async -> DictationLanguage {
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else { return DictationLanguage(id: "en-US") }
            return await AppleSpeech.defaultLanguage()
        case .parakeetEnglish, .parakeetEnglishV2:
            return DictationLanguage(id: "en")
        case .canary:
            // The person's own language, when Canary knows it.
            let code = Locale.preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
            return DictationLanguage(id: code.flatMap { CanaryEngine.languageCodes.contains($0) ? $0 : nil } ?? "en")
        case .nemotron, .parakeet, .parakeetSmall, .whisper, .whisperLarge, .whisperSmall:
            return .automatic
        }
    }

    public func download(
        _ model: DictationModel,
        language: DictationLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        do {
            switch model {
            case .apple:
                guard #available(macOS 26.0, *) else {
                    throw DictationError.unavailable("Apple's speech model needs macOS 26 or later.")
                }
                try await AppleSpeech.download(language, progress: progress)
            case .parakeetEnglish: try await parakeetEnglish.download(progress: progress)
            case .nemotron: try await nemotron.download(progress: progress)
            case .canary: try await canary.download(progress: progress)
            case .parakeet, .parakeetEnglishV2, .parakeetSmall: try await parakeets[model]?.download(progress: progress)
            case .whisper, .whisperLarge, .whisperSmall: try await whispers[model]?.download(progress: progress)
            }
        } catch let error as DictationError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw DictationError.failed("The download stopped: \(error.localizedDescription)")
        }
    }

    public func removeDownload(of model: DictationModel) async throws {
        switch model {
        case .apple: break
        case .parakeetEnglish: try await parakeetEnglish.remove()
        case .nemotron: try await nemotron.remove()
        case .canary: try await canary.remove()
        case .parakeet, .parakeetEnglishV2, .parakeetSmall: try await parakeets[model]?.remove()
        case .whisper, .whisperLarge, .whisperSmall: try await whispers[model]?.remove()
        }
    }

    public func startSession(
        model: DictationModel,
        language: DictationLanguage,
        words: [String]
    ) async throws -> any DictationSession {
        unloadTask?.cancel()
        unloadTask = nil
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else {
                throw DictationError.unavailable("Apple's speech model needs macOS 26 or later.")
            }
            return try await AppleSpeech.startSession(language: language, words: words)
        case .parakeetEnglish: return try await parakeetEnglish.startSession(language: language)
        case .nemotron: return try await nemotron.startSession(language: language)
        case .canary: return try await canary.startSession(language: language)
        case .parakeet, .parakeetEnglishV2, .parakeetSmall:
            guard let engine = parakeets[model] else { throw DictationError.modelNotReady(model) }
            return try await engine.startSession()
        case .whisper, .whisperLarge, .whisperSmall:
            guard let engine = whispers[model] else { throw DictationError.modelNotReady(model) }
            return try await engine.startSession(language: language, words: words)
        }
    }

    public func prepare(_ model: DictationModel, language: DictationLanguage) async {
        unloadTask?.cancel()
        unloadTask = nil
        switch model {
        case .apple: break
        case .parakeetEnglish: await parakeetEnglish.prepare(language: language)
        case .nemotron: await nemotron.prepare(language: language)
        case .canary: await canary.prepare(language: language)
        case .parakeet, .parakeetEnglishV2, .parakeetSmall: await parakeets[model]?.prepare()
        case .whisper, .whisperLarge, .whisperSmall: await whispers[model]?.prepare()
        }
    }

    public func microphones() async -> [Microphone] {
        AudioDevices.microphones()
    }

    public func useMicrophone(_ id: String?) async {
        AudioDevices.chosenMicrophone = id
    }

    public func unloadModels(after seconds: TimeInterval?) async {
        unloadTask?.cancel()
        unloadTask = nil
        guard let seconds else { return }
        unloadTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self.unloadAll()
        }
    }

    private func unloadAll() async {
        await parakeetEnglish.unload()
        await nemotron.unload()
        await canary.unload()
        for engine in parakeets.values { await engine.unload() }
        for engine in whispers.values { await engine.unload() }
    }

    private static func sorted(_ codes: [String]) -> [DictationLanguage] {
        codes.map(DictationLanguage.init(id:)).sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
