import Foundation
import OmanCore

/// Dictation's speech models: Apple's, part of macOS 26 and later, and the ones downloaded once from Settings.
/// Each runs on the Mac, so the sound never leaves it. A downloaded model stays loaded after a dictation, so the
/// next one starts at once, until `unloadModels(after:)` frees it.
public actor SpeechService: SpeechRecognizing {
    private let parakeetEnglish: StreamingEngine
    private let nemotron: StreamingEngine
    private let parakeet: ParakeetEngine
    private let whisper: WhisperEngine
    private var unloadTask: Task<Void, Never>?

    /// `modelsDirectory` holds the downloaded models, one folder each, so removing one deletes its folder.
    public init(modelsDirectory: URL = SpeechService.defaultModelsDirectory) {
        parakeetEnglish = StreamingEngine(
            kind: .parakeetEnglish,
            root: modelsDirectory.appendingPathComponent("parakeet-unified-en", isDirectory: true)
        )
        nemotron = StreamingEngine(
            kind: .nemotron,
            root: modelsDirectory.appendingPathComponent("nemotron-unified", isDirectory: true)
        )
        parakeet = ParakeetEngine(root: modelsDirectory.appendingPathComponent("parakeet", isDirectory: true))
        whisper = WhisperEngine(root: modelsDirectory.appendingPathComponent("whisper", isDirectory: true))
    }

    /// Beside the database, in Application Support.
    public static var defaultModelsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("oman/SpeechModels", isDirectory: true)
    }

    public func status(of model: DictationModel, language: DictationLanguage) async -> DictationModelStatus {
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else {
                return .unavailable("Apple's speech model needs macOS 26 or later. The others work here.")
            }
            return await AppleSpeech.status(of: language)
        case .parakeetEnglish:
            return await parakeetEnglish.isDownloaded ? .ready : .needsDownload(bytes: model.downloadSize)
        case .nemotron:
            return await nemotron.isDownloaded ? .ready : .needsDownload(bytes: model.downloadSize)
        case .parakeet:
            return await parakeet.isDownloaded ? .ready : .needsDownload(bytes: model.downloadSize)
        case .whisper:
            return await whisper.isDownloaded ? .ready : .needsDownload(bytes: model.downloadSize)
        }
    }

    public func languages(for model: DictationModel) async -> [DictationLanguage] {
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else { return [] }
            return await AppleSpeech.languages()
        case .parakeetEnglish:
            return [DictationLanguage(id: "en")]
        case .nemotron:
            return [.automatic] + Self.sorted(StreamingEngine.nemotronLanguages)
        case .parakeet:
            // Parakeet can't be told the language, so the only choice is to let it work it out.
            return [.automatic]
        case .whisper:
            return [.automatic] + WhisperEngine.languages
        }
    }

    /// Every language a model knows, as ISO codes, for showing which of the person's languages it covers.
    public func spokenLanguages(of model: DictationModel) async -> [String] {
        switch model {
        case .parakeet: ParakeetEngine.languageCodes
        case .nemotron: StreamingEngine.nemotronLanguages
        default: await languages(for: model).filter { !$0.isAutomatic }.map(\.id)
        }
    }

    public func defaultLanguage(for model: DictationModel) async -> DictationLanguage {
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else { return DictationLanguage(id: "en-US") }
            return await AppleSpeech.defaultLanguage()
        case .parakeetEnglish:
            return DictationLanguage(id: "en")
        case .nemotron, .parakeet, .whisper:
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
            case .parakeetEnglish:
                try await parakeetEnglish.download(progress: progress)
            case .nemotron:
                try await nemotron.download(progress: progress)
            case .parakeet:
                try await parakeet.download(progress: progress)
            case .whisper:
                try await whisper.download(progress: progress)
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
        case .apple:
            // Part of macOS, which manages its files itself.
            break
        case .parakeetEnglish:
            try await parakeetEnglish.remove()
        case .nemotron:
            try await nemotron.remove()
        case .parakeet:
            try await parakeet.remove()
        case .whisper:
            try await whisper.remove()
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
        case .parakeetEnglish:
            return try await parakeetEnglish.startSession(language: language)
        case .nemotron:
            return try await nemotron.startSession(language: language)
        case .parakeet:
            return try await parakeet.startSession()
        case .whisper:
            return try await whisper.startSession(language: language, words: words)
        }
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

    public func prepare(_ model: DictationModel, language: DictationLanguage) async {
        unloadTask?.cancel()
        unloadTask = nil
        switch model {
        case .apple: break
        case .parakeetEnglish: await parakeetEnglish.prepare(language: language)
        case .nemotron: await nemotron.prepare(language: language)
        case .parakeet: await parakeet.prepare()
        case .whisper: await whisper.prepare()
        }
    }

    private func unloadAll() async {
        await parakeetEnglish.unload()
        await nemotron.unload()
        await parakeet.unload()
        await whisper.unload()
    }

    private static func sorted(_ codes: [String]) -> [DictationLanguage] {
        codes.map(DictationLanguage.init(id:)).sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
