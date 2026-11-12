import Foundation

/// The tokens one Claude request used, split the way Anthropic prices them.
public struct TokenUsage: Equatable, Sendable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite5m: Int
    public var cacheWrite1h: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    /// Every token of the prompt, cached or not, which is what decides Haiku 5.5's rate card.
    public var promptTokens: Int { input + cacheRead + cacheWrite5m + cacheWrite1h }
}

/// What one request used and cost. Only counts are kept, never the text.
public struct UsageEntry: Equatable, Sendable {
    public let date: Date
    /// The model that answered, as Anthropic named it.
    public let model: String
    public let tokens: TokenUsage
    /// US dollars, estimated at list prices when the request finished.
    public let cost: Double
    /// What the request was for. Nil for requests from before OmanAI kept it.
    public let kind: WritingTask.Kind?

    public init(date: Date, model: String, tokens: TokenUsage, cost: Double, kind: WritingTask.Kind? = nil) {
        self.date = date
        self.model = model
        self.tokens = tokens
        self.cost = cost
        self.kind = kind
    }
}

extension WritingTask {
    /// What a request was for, on the Spending page. A change asked for, or Try again, counts as the task it
    /// changes.
    public enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
        case proofread, rewrite, explain, compose

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .proofread: "Proofread"
            case .rewrite: "Rewrite"
            case .explain: "Explain"
            case .compose: "Compose"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .proofread: .proofread
        case .rewrite: .rewrite
        case .explain: .explain
        case .compose: .compose
        }
    }
}

/// One text OmanAI wrote, with any model: what for, in which app, and whether it was put back there with Replace
/// or Insert. Only these facts are kept, never the text.
public struct WritingAction: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let kind: WritingTask.Kind
    /// The model chosen, as `WritingModel.rawValue`.
    public let model: String
    public let appName: String?
    public var applied: Bool
    /// For a proofread, how many places it changed, which the Lab follows week by week. Nil for the rest, and for
    /// proofreads from before this was kept.
    public let changes: Int?

    public init(
        id: UUID = UUID(),
        date: Date,
        kind: WritingTask.Kind,
        model: String,
        appName: String?,
        applied: Bool = false,
        changes: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.model = model
        self.appName = appName
        self.applied = applied
        self.changes = changes
    }
}

public protocol ActionStore: Sendable {
    func recordAction(_ action: WritingAction) throws
    /// The text was put back into its app.
    func markActionApplied(id: UUID) throws
    /// Oldest first.
    func actions(since date: Date) throws -> [WritingAction]
}
