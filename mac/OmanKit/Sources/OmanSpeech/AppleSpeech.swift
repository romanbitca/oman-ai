import AVFoundation
import Foundation
import OmanCore
import Speech

/// Apple's speech model, part of macOS 26 and later. Its newer transcriber is used where it knows the language,
/// and the one behind macOS's own dictation everywhere else, which knows more languages.
@available(macOS 26.0, *)
enum AppleSpeech {
    static func languages() async -> [DictationLanguage] {
        var identifiers = Set<String>()
        if SpeechTranscriber.isAvailable {
            for locale in await SpeechTranscriber.supportedLocales {
                identifiers.insert(locale.identifier(.bcp47))
            }
        }
        for locale in await DictationTranscriber.supportedLocales {
            identifiers.insert(locale.identifier(.bcp47))
        }
        return identifiers.map(DictationLanguage.init(id:)).sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// The Mac's own language when the model knows it, otherwise English.
    static func defaultLanguage() async -> DictationLanguage {
        if let match = await locale(equivalentTo: Locale.current) {
            return DictationLanguage(id: match.identifier(.bcp47))
        }
        return DictationLanguage(id: "en-US")
    }

    static func status(of language: DictationLanguage) async -> DictationModelStatus {
        guard let modules = await modules(for: language) else {
            return .unavailable("Apple's model doesn't know this language. Choose another one.")
        }
        switch await AssetInventory.status(forModules: modules) {
        case .installed:
            return .ready
        case .supported, .downloading:
            return .needsDownload(bytes: nil)
        case .unsupported:
            return .unavailable("This Mac can't run Apple's model for this language.")
        @unknown default:
            return .unavailable("Apple's model isn't available right now.")
        }
    }

    static func download(_ language: DictationLanguage, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let modules = await modules(for: language) else {
            throw DictationError.unavailable("Apple's model doesn't know this language.")
        }
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
            progress(1)
            return
        }
        let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { progressObject, _ in
            progress(progressObject.fractionCompleted)
        }
        defer { observation.invalidate() }
        try await request.downloadAndInstall()
        progress(1)
    }

    static func startSession(language: DictationLanguage, words: [String]) async throws -> any DictationSession {
        guard let modules = await modules(for: language), let transcriber = modules.first else {
            throw DictationError.unavailable("Apple's model doesn't know this language.")
        }
        guard await AssetInventory.status(forModules: modules) == .installed else {
            throw DictationError.modelNotReady(.apple)
        }
        return try await AppleDictationSession.start(transcriber: transcriber, words: words)
    }

    /// Reads a recording, for the tests that check the model without a microphone.
    static func transcribe(file url: URL, language: DictationLanguage) async throws -> String {
        guard let modules = await modules(for: language), let transcriber = modules.first else {
            throw DictationError.unavailable("Apple's model doesn't know this language.")
        }
        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: modules)
        let collector = Task { try await finalText(of: transcriber) }
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        return try await collector.value
    }

    private static func finalText(of module: any SpeechModule) async throws -> String {
        var text = ""
        if let transcriber = module as? SpeechTranscriber {
            for try await result in transcriber.results where result.isFinal {
                text = LiveTranscript.join(text, String(result.text.characters))
            }
        } else if let transcriber = module as? DictationTranscriber {
            for try await result in transcriber.results where result.isFinal {
                text = LiveTranscript.join(text, String(result.text.characters))
            }
        }
        return text
    }

    /// The transcriber for a language: the newer one where it knows the language, otherwise the dictation one.
    static func modules(for language: DictationLanguage) async -> [any SpeechModule]? {
        let wanted = Locale(identifier: language.id)
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) {
            return [SpeechTranscriber(locale: locale, preset: .progressiveTranscription)]
        }
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: wanted) {
            let preset = DictationTranscriber.Preset.progressiveLongDictation
            return [DictationTranscriber(
                locale: locale,
                contentHints: preset.contentHints,
                transcriptionOptions: preset.transcriptionOptions.union([.punctuation]),
                reportingOptions: preset.reportingOptions.union([.volatileResults]),
                attributeOptions: preset.attributeOptions
            )]
        }
        return nil
    }

    private static func locale(equivalentTo locale: Locale) async -> Locale? {
        if SpeechTranscriber.isAvailable, let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return match
        }
        return await DictationTranscriber.supportedLocale(equivalentTo: locale)
    }
}

/// One dictation through Apple's model: the microphone feeds the analyzer, and its results become live words.
@available(macOS 26.0, *)
final class AppleDictationSession: DictationSession, @unchecked Sendable {
    let updates: AsyncStream<DictationUpdate>
    private let updatesContinuation: AsyncStream<DictationUpdate>.Continuation
    private let analyzer: SpeechAnalyzer
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let capture: MicrophoneCapture
    private let lock = NSLock()
    private var confirmed = ""
    private var tentative = ""
    private var resultsTask: Task<Void, Error>?

    private init(
        analyzer: SpeechAnalyzer,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        capture: MicrophoneCapture,
        updates: AsyncStream<DictationUpdate>,
        updatesContinuation: AsyncStream<DictationUpdate>.Continuation
    ) {
        self.analyzer = analyzer
        self.inputContinuation = inputContinuation
        self.capture = capture
        self.updates = updates
        self.updatesContinuation = updatesContinuation
    }

    static func start(transcriber: any SpeechModule, words: [String]) async throws -> AppleDictationSession {
        let modules = [transcriber]
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw DictationError.failed("Apple's model can't take the microphone's sound.")
        }
        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)
        )
        if !words.isEmpty {
            // Words the model should expect, such as names it wouldn't know.
            let context = AnalysisContext()
            context.contextualStrings[.general] = words
            try? await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: format)

        let (inputs, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (updates, updatesContinuation) = AsyncStream.makeStream(of: DictationUpdate.self)
        let capture = MicrophoneCapture(
            targetFormat: format,
            onAudio: { buffer in inputContinuation.yield(AnalyzerInput(buffer: buffer)) },
            onLevel: { level in updatesContinuation.yield(.level(level)) }
        )
        let session = AppleDictationSession(
            analyzer: analyzer,
            inputContinuation: inputContinuation,
            capture: capture,
            updates: updates,
            updatesContinuation: updatesContinuation
        )
        session.resultsTask = Task { try await session.readResults(of: transcriber) }
        try await analyzer.start(inputSequence: inputs)
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
        inputContinuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await resultsTask?.value
        updatesContinuation.finish()
        return lock.withLock { LiveTranscript.join(confirmed, tentative) }
    }

    func cancel() async {
        capture.stop()
        inputContinuation.finish()
        await analyzer.cancelAndFinishNow()
        resultsTask?.cancel()
        updatesContinuation.finish()
    }

    private func readResults(of module: any SpeechModule) async throws {
        if let transcriber = module as? SpeechTranscriber {
            for try await result in transcriber.results {
                receive(String(result.text.characters), isFinal: result.isFinal)
            }
        } else if let transcriber = module as? DictationTranscriber {
            for try await result in transcriber.results {
                receive(String(result.text.characters), isFinal: result.isFinal)
            }
        }
    }

    private func receive(_ text: String, isFinal: Bool) {
        let live = lock.withLock {
            if isFinal {
                confirmed = LiveTranscript.join(confirmed, text)
                tentative = ""
            } else {
                tentative = text
            }
            return LiveTranscript(confirmed: confirmed, tentative: tentative)
        }
        updatesContinuation.yield(.transcript(live))
    }
}
