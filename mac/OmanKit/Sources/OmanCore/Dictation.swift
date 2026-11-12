import Foundation

/// Where the glass pill with the live words appears while the person dictates into another app.
public enum DictationPillPosition: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Hanging from the menu bar icon, where the panel opens.
    case menuBar
    /// Above the Dock, in the middle of the screen.
    case bottom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .menuBar: "Under the menu bar icon"
        case .bottom: "At the bottom of the screen"
        }
    }
}

/// How the pill shows the live words. Both put the seconds and Done in a row of their own, outside the words.
public enum DictationPillStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The moving wave, the seconds and Done on top, and the words below them in a glass card.
    case card
    /// The words float on a soft blur with no box around them, above the wave, the seconds and Done.
    case floating

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .card: "Card"
        case .floating: "Floating"
        }
    }
}

/// A language to listen for, or `automatic` for a model that works the language out itself.
public struct DictationLanguage: Hashable, Codable, Sendable, Identifiable {
    public static let automatic = DictationLanguage(id: "auto")

    /// "auto", or a locale identifier such as "en-US" or "ro".
    public let id: String

    public init(id: String) {
        self.id = id
    }

    public var isAutomatic: Bool { id == Self.automatic.id }

    public var displayName: String {
        if isAutomatic { return "Automatic" }
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }
}

/// The words heard so far. `confirmed` will not change any more; `tentative` is the model's current guess at
/// the last few words and may still change.
public struct LiveTranscript: Equatable, Sendable {
    public var confirmed: String
    public var tentative: String

    public init(confirmed: String = "", tentative: String = "") {
        self.confirmed = confirmed
        self.tentative = tentative
    }

    public var text: String {
        LiveTranscript.join(confirmed, tentative)
    }

    public var isEmpty: Bool { text.isEmpty }

    /// Two pieces of speech with one space between them, whatever spacing each brought along.
    public static func join(_ first: String, _ second: String) -> String {
        let head = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }
}

/// A dictation that was put into an app or the panel, kept so the person can find it again. Only its text is
/// kept, never the sound.
public struct SavedDictation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let duration: TimeInterval
    /// The model's identifier, as `DictationModel.rawValue`.
    public let model: String
    public let language: String?
    public let appName: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        text: String,
        duration: TimeInterval,
        model: String,
        language: String?,
        appName: String?
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.duration = duration
        self.model = model
        self.language = language
        self.appName = appName
    }
}

public protocol DictationStore: Sendable {
    func saveDictation(_ dictation: SavedDictation) throws
    /// Newest first.
    func savedDictations() throws -> [SavedDictation]
    func latestDictation() throws -> SavedDictation?
    func deleteDictation(id: UUID) throws
    func deleteAllDictations() throws
    /// Deletes all but the newest `count`.
    func trimDictations(keepingNewest count: Int) throws
}

/// A speech model that turns what the person says into text. Every one runs on the Mac, so the sound never
/// leaves it.
public enum DictationModel: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Apple's speech model, part of macOS 26 and later. macOS downloads each language the first time it is used.
    case apple
    /// NVIDIA's Parakeet Unified, English only, made to stream: words appear as they are said.
    case parakeetEnglish = "parakeet-unified-en"
    /// NVIDIA's Nemotron Unified, made to stream like Parakeet Unified, in 25 European languages.
    case nemotron = "nemotron-unified"
    /// Moondream's Parakeet Ultra: the most accurate Parakeet in its 25 European languages, which it works out.
    case parakeet = "parakeet-v3"
    /// NVIDIA's Canary 1B v2, in the same 25 European languages, told which one is spoken.
    case canary = "canary-1b-v2"
    /// NVIDIA's Parakeet TDT v2, English only, the most accurate Parakeet for English.
    case parakeetEnglishV2 = "parakeet-tdt-v2"
    /// OpenAI's Whisper large-v3: about a hundred languages, and the most accurate in many of them.
    case whisperLarge = "whisper-large-v3"
    /// OpenAI's Whisper large-v3 turbo: the same languages, faster, a little less accurate.
    case whisper = "whisper-large-v3-turbo"
    /// Moondream's Parakeet Redux: Parakeet's 25 European languages in a third of the download.
    case parakeetSmall = "parakeet-redux"
    /// OpenAI's Whisper small: about a hundred languages in a small download, less accurate.
    case whisperSmall = "whisper-small"

    public static let `default`: DictationModel = .apple

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apple: "Apple"
        case .parakeetEnglish: "Parakeet Unified"
        case .nemotron: "Nemotron Unified"
        case .parakeet: "Parakeet Ultra"
        case .canary: "Canary 1B v2"
        case .parakeetEnglishV2: "Parakeet TDT v2"
        case .whisperLarge: "Whisper Large v3"
        case .whisper: "Whisper Large v3 Turbo"
        case .parakeetSmall: "Parakeet Redux"
        case .whisperSmall: "Whisper Small"
        }
    }

    /// One line for the list of models in Settings.
    public var summary: String {
        switch self {
        case .apple: "Built into macOS, in one language at a time."
        case .parakeetEnglish: "The fastest and most accurate for English."
        case .nemotron: "Live in 25 European languages. Choose yours, or let it work it out."
        case .parakeet: "Very accurate in 25 European languages, worked out as you speak."
        case .canary: "Very accurate in 25 European languages. Choose yours."
        case .parakeetEnglishV2: "Very accurate English, with every word as it was said."
        case .whisperLarge: "The most languages, about a hundred, and the most accurate in many."
        case .whisper: "About a hundred languages, faster than Whisper Large v3."
        case .parakeetSmall: "Parakeet's 25 European languages in a third of the download."
        case .whisperSmall: "About a hundred languages in a small download, less accurate."
        }
    }

    /// How models are grouped in Settings.
    public enum Group: String, CaseIterable, Sendable {
        /// Made to stream: words appear while they are being said.
        case live
        /// Read what was said again about every second: words follow a moment later, often more accurately.
        case accurate
        /// Small downloads, for a Mac short on space.
        case small
    }

    public var group: Group {
        switch self {
        case .apple, .parakeetEnglish, .nemotron: .live
        case .parakeet, .canary, .parakeetEnglishV2, .whisperLarge, .whisper: .accurate
        case .parakeetSmall, .whisperSmall: .small
        }
    }

    /// Whether the model is a download the person starts, rather than part of macOS.
    public var isDownloaded: Bool { self != .apple }

    /// Made to stream, so words appear while they are being said. The others read the sound again every second.
    public var isLive: Bool { group == .live }

    /// How soon the words show, in plain words for Settings.
    public var pace: String {
        switch self {
        case .apple, .parakeetEnglish: "Words as you speak"
        case .nemotron: "Words within a second"
        case .parakeet, .parakeetEnglishV2, .parakeetSmall, .canary: "Words a moment later"
        case .whisper, .whisperSmall: "Words a second or two later"
        case .whisperLarge: "Words a few seconds later"
        }
    }

    /// What its download comes to, measured from the files. Nil for Apple's, which macOS downloads per language.
    public var downloadSize: Int64? {
        switch self {
        case .apple: nil
        case .parakeetEnglish: 609_000_000
        case .nemotron: 621_000_000
        case .parakeet: 632_000_000
        case .canary: 637_000_000
        case .parakeetEnglishV2: 465_000_000
        case .whisperLarge: 950_000_000
        case .whisper: 629_000_000
        case .parakeetSmall: 220_000_000
        case .whisperSmall: 219_000_000
        }
    }

    /// The oldest macOS the model runs on, as a major version.
    public var minimumMacOS: Int {
        switch self {
        case .apple: 26
        case .parakeetSmall: 15
        default: 14
        }
    }
}

/// How long a downloaded model stays loaded after a dictation, ready for the next one. Unloading frees the memory
/// it takes, and the next dictation then takes a moment to load it again.
public enum ModelUnloadDelay: String, Codable, CaseIterable, Sendable, Identifiable {
    case immediately, oneMinute, fiveMinutes, fifteenMinutes, oneHour, never

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .immediately: "Right away"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        case .fifteenMinutes: "After 15 minutes"
        case .oneHour: "After an hour"
        case .never: "Never"
        }
    }

    public var seconds: TimeInterval? {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .oneHour: 3_600
        case .never: nil
        }
    }
}

/// What a model needs before it can listen.
public enum DictationModelStatus: Equatable, Sendable {
    case ready
    /// Needs a download first, of about this many bytes when that is known.
    case needsDownload(bytes: Int64?)
    /// Can't run here. The text is a sentence for the person.
    case unavailable(String)
}

public enum DictationUpdate: Equatable, Sendable {
    case transcript(LiveTranscript)
    /// How loud the microphone is, from 0 to 1.
    case level(Float)
    /// The model is being loaded into memory, or has finished. The microphone listens all the while, so nothing
    /// said meanwhile is lost; its words appear once the model is ready.
    case loadingModel(Bool)
}

/// One dictation in progress.
public protocol DictationSession: AnyObject, Sendable {
    /// The live words and the microphone's level, until the session ends.
    var updates: AsyncStream<DictationUpdate> { get }
    /// Stops listening, lets the model settle the last words and returns all of them.
    func finish() async throws -> String
    /// Stops at once. What was heard is thrown away.
    func cancel() async
}

public protocol SpeechRecognizing: Sendable {
    func status(of model: DictationModel, language: DictationLanguage) async -> DictationModelStatus
    /// The languages a model can listen for, with `DictationLanguage.automatic` first when it can work the
    /// language out itself.
    func languages(for model: DictationModel) async -> [DictationLanguage]
    /// Every language a model knows, as identifiers such as "en" or "ro-RO", for showing which of the person's
    /// languages it covers. Unlike `languages(for:)`, this lists them even for a model that can't be told one.
    func spokenLanguages(of model: DictationModel) async -> [String]
    /// The language to use when the person has not chosen one.
    func defaultLanguage(for model: DictationModel) async -> DictationLanguage
    /// Downloads what the model needs for the language. `progress` goes from 0 to 1.
    func download(
        _ model: DictationModel,
        language: DictationLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
    /// Deletes a downloaded model's files. Apple's model is part of macOS and has none.
    func removeDownload(of model: DictationModel) async throws
    /// Starts listening to the microphone. `words` are the person's own words, such as names, for a model that
    /// can be told to expect them.
    func startSession(
        model: DictationModel,
        language: DictationLanguage,
        words: [String]
    ) async throws -> any DictationSession
    /// Frees the memory of loaded models after `seconds` without a dictation, or never with nil.
    func unloadModels(after seconds: TimeInterval?) async
    /// The microphones the Mac has now.
    func microphones() async -> [Microphone]
    /// Listens to this microphone from the next dictation, or to the one chosen in System Settings with nil.
    func useMicrophone(_ id: String?) async
    /// Loads a downloaded model into memory ahead of a dictation, so it starts at once. Does nothing for a model
    /// that isn't downloaded, or for Apple's, which macOS keeps ready itself.
    func prepare(_ model: DictationModel, language: DictationLanguage) async
}

public enum DictationError: Error, Equatable, Sendable {
    case microphoneDenied
    case noMicrophone
    case modelNotReady(DictationModel)
    case unavailable(String)
    case failed(String)

    public var message: String {
        switch self {
        case .microphoneDenied:
            "OmanAI isn't allowed to use the microphone. Allow it in System Settings, under Privacy & Security."
        case .noMicrophone:
            "No microphone was found."
        case .modelNotReady(let model):
            "\(model.displayName) needs a download first. Open Settings, then Dictation."
        case .unavailable(let reason):
            reason
        case .failed(let reason):
            reason
        }
    }
}

public enum MicrophoneAccess: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// A modifier key that starts a dictation on its own, without another key: Option or Command, on the left or
/// right of the space bar.
public enum ModifierKey: String, Codable, CaseIterable, Sendable, Identifiable {
    case rightOption, leftOption, rightCommand, leftCommand

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rightOption: "Right Option"
        case .leftOption: "Left Option"
        case .rightCommand: "Right Command"
        case .leftCommand: "Left Command"
        }
    }

    public var symbol: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .leftOption: "Left ⌥"
        case .rightCommand: "Right ⌘"
        case .leftCommand: "Left ⌘"
        }
    }

    /// The key code macOS reports for it in a flags-changed event.
    public var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .leftOption: 58
        case .rightCommand: 54
        case .leftCommand: 55
        }
    }

    public init?(keyCode: UInt16) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }
}

/// What a modifier key on its own did: went down, came up, or another key was pressed while it was down, which
/// makes it part of an ordinary shortcut rather than a dictation.
public enum ModifierKeyEvent: Equatable, Sendable {
    case down(ModifierKey)
    case up(ModifierKey)
    case otherKey
}

/// A key pressed after the words are pasted, to send a message in apps where Return sends.
public enum DictationSubmit: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, returnKey, commandReturn

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Nothing"
        case .returnKey: "Return"
        case .commandReturn: "⌘Return"
        }
    }
}

/// How many transcripts are kept.
public enum DictationHistory: String, Codable, CaseIterable, Sendable, Identifiable {
    case off, last10, last50, all

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "None"
        case .last10: "The last 10"
        case .last50: "The last 50"
        case .all: "All of them"
        }
    }

    /// The most kept, or nil for no limit.
    public var limit: Int? {
        switch self {
        case .off: 0
        case .last10: 10
        case .last50: 50
        case .all: nil
        }
    }
}

/// A microphone the Mac has, as macOS names it.
public struct Microphone: Identifiable, Hashable, Sendable {
    /// macOS's lasting identifier for the device.
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum DictationSound: Sendable {
    case start, finish
}
