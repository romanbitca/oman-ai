import Foundation
import OmanCore

/// Dictation's speech models: Apple's, part of macOS 26 and later, and two that are downloaded once, Parakeet and
/// Whisper. Each runs on the Mac, so the sound never leaves it.
public final class SpeechService: SpeechRecognizing {
    private let parakeet: ParakeetEngine
    private let whisper: WhisperEngine

    /// `modelsDirectory` holds the downloaded models, one folder each, so removing one deletes its folder.
    public init(modelsDirectory: URL = SpeechService.defaultModelsDirectory) {
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
                return .unavailable("Apple's speech model needs macOS 26 or later. Parakeet and Whisper work here.")
            }
            return await AppleSpeech.status(of: language)
        case .parakeet:
            return await parakeet.isDownloaded ? .ready : .needsDownload(bytes: ParakeetEngine.downloadSize)
        case .whisper:
            return await whisper.isDownloaded ? .ready : .needsDownload(bytes: WhisperEngine.downloadSize)
        }
    }

    public func languages(for model: DictationModel) async -> [DictationLanguage] {
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else { return [] }
            return await AppleSpeech.languages()
        case .parakeet:
            // Parakeet can't be told the language, so the only choice is to let it work it out.
            return [.automatic]
        case .whisper:
            return [.automatic] + WhisperEngine.languages
        }
    }

    public func defaultLanguage(for model: DictationModel) async -> DictationLanguage {
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else { return DictationLanguage(id: "en-US") }
            return await AppleSpeech.defaultLanguage()
        case .parakeet, .whisper:
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
        case .parakeet:
            try await parakeet.remove()
        case .whisper:
            try await whisper.remove()
        }
    }

    public func startSession(model: DictationModel, language: DictationLanguage) async throws -> any DictationSession {
        switch model {
        case .apple:
            guard #available(macOS 26.0, *) else {
                throw DictationError.unavailable("Apple's speech model needs macOS 26 or later.")
            }
            return try await AppleSpeech.startSession(language: language)
        case .parakeet:
            return try await parakeet.startSession()
        case .whisper:
            return try await whisper.startSession(language: language)
        }
    }
}
