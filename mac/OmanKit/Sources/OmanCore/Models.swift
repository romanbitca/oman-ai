import Foundation

public enum WritingModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"
    case opus = "claude-opus-5-5"
    case appleOnDevice = "apple-on-device"

    public static let `default`: WritingModel = .haiku

    public var id: String { rawValue }

    public var isLocal: Bool { self == .appleOnDevice }

    public var displayName: String {
        switch self {
        case .haiku: "Haiku 5.5"
        case .sonnet: "Sonnet 5.5"
        case .opus: "Opus 5.5"
        case .appleOnDevice: "Apple on-device"
        }
    }
}

public struct StyleSample: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public struct WritingStyle: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var note: String
    public var samples: [StyleSample]

    public init(id: UUID = UUID(), name: String, note: String = "", samples: [StyleSample] = []) {
        self.id = id
        self.name = name
        self.note = note
        self.samples = samples
    }
}

public struct SourceApp: Equatable, Sendable {
    public let name: String
    public let bundleID: String?
    public let processID: Int32

    public init(name: String, bundleID: String?, processID: Int32) {
        self.name = name
        self.bundleID = bundleID
        self.processID = processID
    }
}

public struct SelectionCapture: Equatable, Sendable {
    /// Nil when OmanAI itself was frontmost, so there is no other app to write into.
    public let app: SourceApp?
    /// Nil when nothing was selected or the app did not expose the selection.
    public let text: String?

    public init(app: SourceApp?, text: String?) {
        self.app = app
        self.text = text
    }
}

public enum InsertOutcome: Equatable, Sendable {
    case inserted
    case selectionChanged
    /// The cursor is somewhere else than when the panel opened. Nothing was pasted; asking again pastes there.
    case focusMoved
    case sourceUnavailable
    case permissionMissing
}

public struct ScreenshotAttachment: Equatable, Sendable {
    public let jpegData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(jpegData: Data, pixelWidth: Int, pixelHeight: Int) {
        self.jpegData = jpegData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct WritingContext: Equatable, Sendable {
    public var pastedText: String
    public var screenshot: ScreenshotAttachment?

    public init(pastedText: String = "", screenshot: ScreenshotAttachment? = nil) {
        self.pastedText = pastedText
        self.screenshot = screenshot
    }
}

public enum WritingTask: Equatable, Sendable {
    case proofread(text: String)
    case rewrite(text: String, instruction: String?)
    case compose(request: String, selectedText: String?)
}

public struct Refinement: Equatable, Sendable {
    public var currentDraft: String
    public var adjustment: String

    public init(currentDraft: String, adjustment: String) {
        self.currentDraft = currentDraft
        self.adjustment = adjustment
    }
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public enum WritingQuality: String, Codable, CaseIterable, Sendable, Identifiable {
    case fast, balanced, best

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fast: "Fast"
        case .balanced: "Balanced"
        case .best: "Best"
        }
    }

    public var detail: String {
        switch self {
        case .fast: "Replies quickest. Right for everyday messages."
        case .balanced: "Takes a little more care over wording."
        case .best: "Thinks hardest. Slower, and costs a little more."
        }
    }

    public var effort: String {
        switch self {
        case .fast: "low"
        case .balanced: "medium"
        case .best: "high"
        }
    }
}

public struct WritingRequest: Equatable, Sendable {
    public var task: WritingTask
    public var style: WritingStyle?
    public var context: WritingContext
    public var refinement: Refinement?
    public var model: WritingModel
    public var quality: WritingQuality
    public var outputLanguage: String?
    public var customInstructions: String?

    public init(
        task: WritingTask,
        style: WritingStyle? = nil,
        context: WritingContext = WritingContext(),
        refinement: Refinement? = nil,
        model: WritingModel = .default,
        quality: WritingQuality = .fast,
        outputLanguage: String? = nil,
        customInstructions: String? = nil
    ) {
        self.task = task
        self.style = style
        self.context = context
        self.refinement = refinement
        self.model = model
        self.quality = quality
        self.outputLanguage = outputLanguage
        self.customInstructions = customInstructions
    }
}

public struct KeyCombo: Codable, Hashable, Sendable {
    public static let command: UInt = 1 << 20
    public static let option: UInt = 1 << 19
    public static let control: UInt = 1 << 18
    public static let shift: UInt = 1 << 17

    public let keyCode: UInt16
    public let modifiers: UInt

    public init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers & (Self.command | Self.option | Self.control | Self.shift)
    }

    /// Without one of these the combination would swallow ordinary typing, unless it is a function key.
    public var isUsable: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0 || Self.functionKeyCodes.contains(keyCode)
    }

    /// ⌘C and ⌘V are the keys OmanAI itself presses to read and replace a selection.
    /// As a shortcut, either one would be set off by OmanAI's own key presses.
    public var isCopyOrPaste: Bool {
        modifiers == Self.command && (keyCode == 8 || keyCode == 9)
    }

    public var displayString: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keyLabels[keyCode] ?? "Key \(keyCode)")
    }

    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    private static let keyLabels: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 76: "⌅", 117: "⌦",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

public enum ShortcutAction: Hashable, Sendable {
    case openPanel, proofread, rewrite, compose
    case style(UUID)
    case acceptResult, copyResult, tryAgain, toggleOriginal

    public static let globalActions: [ShortcutAction] = [.openPanel, .proofread, .rewrite, .compose]
    public static let panelActions: [ShortcutAction] = [.acceptResult, .copyResult, .tryAgain, .toggleOriginal]

    public var isGlobal: Bool {
        switch self {
        case .openPanel, .proofread, .rewrite, .compose, .style: true
        case .acceptResult, .copyResult, .tryAgain, .toggleOriginal: false
        }
    }

    public var storageKey: String {
        switch self {
        case .openPanel: "openPanel"
        case .proofread: "proofread"
        case .rewrite: "rewrite"
        case .compose: "compose"
        case .style(let id): "style:\(id.uuidString)"
        case .acceptResult: "acceptResult"
        case .copyResult: "copyResult"
        case .tryAgain: "tryAgain"
        case .toggleOriginal: "toggleOriginal"
        }
    }

    public init?(storageKey: String) {
        if storageKey.hasPrefix("style:") {
            guard let id = UUID(uuidString: String(storageKey.dropFirst("style:".count))) else { return nil }
            self = .style(id)
            return
        }
        guard let match = (Self.globalActions + Self.panelActions).first(where: { $0.storageKey == storageKey }) else {
            return nil
        }
        self = match
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var appearance: AppearanceMode = .system
    public var quality: WritingQuality = .fast
    public var outputLanguage = ""
    public var customInstructions = ""
    public var defaultStyleID: UUID?
    public var remembersStylePerApp = true
    public var includesScreenByDefault = false
    public var keepsPanelOpen = false
    /// Global shortcuts start empty so OmanAI never takes a combination another app is using.
    public var shortcuts: [String: KeyCombo] = [
        ShortcutAction.acceptResult.storageKey: KeyCombo(keyCode: 36, modifiers: KeyCombo.command),
        ShortcutAction.copyResult.storageKey: KeyCombo(keyCode: 8, modifiers: KeyCombo.command | KeyCombo.shift),
        ShortcutAction.tryAgain.storageKey: KeyCombo(keyCode: 15, modifiers: KeyCombo.command),
        ShortcutAction.toggleOriginal.storageKey: KeyCombo(keyCode: 31, modifiers: KeyCombo.command),
    ]

    public init() {}

    // Missing keys keep their defaults, so settings saved by an older version still load.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppPreferences()
        appearance = (try? values.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? defaults.appearance
        quality = (try? values.decodeIfPresent(WritingQuality.self, forKey: .quality)) ?? defaults.quality
        outputLanguage = (try? values.decodeIfPresent(String.self, forKey: .outputLanguage)) ?? defaults.outputLanguage
        customInstructions =
            (try? values.decodeIfPresent(String.self, forKey: .customInstructions)) ?? defaults.customInstructions
        defaultStyleID = try? values.decodeIfPresent(UUID.self, forKey: .defaultStyleID)
        remembersStylePerApp =
            (try? values.decodeIfPresent(Bool.self, forKey: .remembersStylePerApp)) ?? defaults.remembersStylePerApp
        includesScreenByDefault =
            (try? values.decodeIfPresent(Bool.self, forKey: .includesScreenByDefault)) ?? defaults.includesScreenByDefault
        keepsPanelOpen = (try? values.decodeIfPresent(Bool.self, forKey: .keepsPanelOpen)) ?? defaults.keepsPanelOpen
        shortcuts = (try? values.decodeIfPresent([String: KeyCombo].self, forKey: .shortcuts)) ?? defaults.shortcuts
    }

    public func combo(for action: ShortcutAction) -> KeyCombo? {
        shortcuts[action.storageKey]
    }

    public mutating func setCombo(_ combo: KeyCombo?, for action: ShortcutAction) {
        shortcuts[action.storageKey] = combo
    }

    public var globalShortcuts: [ShortcutAction: KeyCombo] {
        var result: [ShortcutAction: KeyCombo] = [:]
        for (key, combo) in shortcuts {
            if let action = ShortcutAction(storageKey: key), action.isGlobal, !combo.isCopyOrPaste {
                result[action] = combo
            }
        }
        return result
    }
}

public enum WritingError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidAPIKey
    case accessDenied(String)
    case billing
    case modelUnavailable
    case rateLimited(retryAfterSeconds: Int?)
    case overloaded
    case requestTooLarge
    case refused
    case truncated
    case noOutput
    case network(String)
    case server(status: Int, message: String)
    case localModel(String)
}

extension WritingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your Anthropic API key in Settings."
        case .invalidAPIKey:
            "Anthropic rejected this API key. Check it in Settings."
        case .accessDenied(let message):
            "This API key isn't allowed to do that. \(message)"
        case .billing:
            "Your Anthropic account is out of credit."
        case .modelUnavailable:
            "This model isn't available for your API key. Choose another in Settings."
        case .rateLimited(let seconds):
            seconds.map { "Rate limit reached. Try again in \($0) seconds." }
                ?? "Rate limit reached. Try again shortly."
        case .overloaded:
            "Claude is overloaded right now. Try again in a moment."
        case .requestTooLarge:
            "This request is too large. Remove some context or style samples."
        case .refused:
            "Claude declined to work on this text."
        case .truncated:
            "The response was cut off before it finished."
        case .noOutput:
            "Claude returned no text. Try again."
        case .network(let message):
            "Couldn't reach Anthropic. \(message)"
        case .server(let status, let message):
            "Anthropic returned an error (\(status)). \(message)"
        case .localModel(let message):
            message
        }
    }
}
