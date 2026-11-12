import FluidAudio
import Foundation
import OmanCore

/// NVIDIA's Canary 1B v2, run by FluidAudio. It knows 25 European languages and is told which one is spoken. It
/// reads a whole recording at once, so while the person speaks everything said so far is read again every second.
actor CanaryEngine {
    static let languageCodes: [String] = CanaryLanguage.allCases.map(\.rawValue)

    private let root: URL
    private var manager: CanaryManager?
    private var loadedLanguage: DictationLanguage?

    init(root: URL) {
        self.root = root
    }

    /// FluidAudio downloads Canary into its own shared folder; where that is gets written here.
    private var locationFile: URL { root.appendingPathComponent("location") }

    private var modelDirectory: URL? {
        guard let path = try? String(contentsOf: locationFile, encoding: .utf8) else { return nil }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        return CanaryModels.modelsExist(at: directory) ? directory : nil
    }

    var isDownloaded: Bool { modelDirectory != nil }

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = try await CanaryModels.download { update in
            progress(update.fractionCompleted * 0.9)
        }
        try Task.checkCancellation()
        try directory.path.write(to: locationFile, atomically: true, encoding: .utf8)
        _ = try await loaded(language: DictationLanguage(id: "en"))
        progress(1)
    }

    func remove() async throws {
        let directory = modelDirectory
        await unload()
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    func unload() async {
        manager = nil
        loadedLanguage = nil
    }

    func prepare(language: DictationLanguage) async {
        guard isDownloaded else { return }
        _ = try? await loaded(language: language)
    }

    func startSession(language: DictationLanguage) async throws -> any DictationSession {
        guard isDownloaded else { throw DictationError.modelNotReady(.canary) }
        return try RereadingDictationSession.start(
            needsLoading: manager == nil || loadedLanguage != language,
            load: { _ = try await self.loaded(language: language) },
            read: { samples in try await self.transcribe(samples, language: language) }
        )
    }

    func transcribe(_ samples: [Float], language: DictationLanguage) async throws -> String {
        let manager = try await loaded(language: language)
        return try await manager.transcribe(audio: samples)
    }

    /// Canary is told the language it hears through its prompt, so another language needs a new prompt.
    private func loaded(language: DictationLanguage) async throws -> CanaryManager {
        if let manager, loadedLanguage == language { return manager }
        guard let directory = modelDirectory else { throw DictationError.modelNotReady(.canary) }
        let spoken = CanaryLanguage(rawValue: language.id) ?? .english
        let models = try CanaryModels.load(from: directory)
        let manager = try CanaryManager(models: models, source: spoken, target: spoken)
        self.manager = manager
        loadedLanguage = language
        return manager
    }
}
