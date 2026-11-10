import Foundation

public enum ClaudeModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"
    case opus = "claude-opus-5-5"

    public static let `default`: ClaudeModel = .haiku

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .haiku: "Haiku 5.5"
        case .sonnet: "Sonnet 5.5"
        case .opus: "Opus 5.5"
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
    /// Nil when oman itself was frontmost, so there is no other app to write into.
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

public struct WritingRequest: Equatable, Sendable {
    public var task: WritingTask
    public var style: WritingStyle?
    public var context: WritingContext
    public var refinement: Refinement?
    public var model: ClaudeModel

    public init(
        task: WritingTask,
        style: WritingStyle? = nil,
        context: WritingContext = WritingContext(),
        refinement: Refinement? = nil,
        model: ClaudeModel = .default
    ) {
        self.task = task
        self.style = style
        self.context = context
        self.refinement = refinement
        self.model = model
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
        }
    }
}
