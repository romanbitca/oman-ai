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

    public init(date: Date, model: String, tokens: TokenUsage, cost: Double) {
        self.date = date
        self.model = model
        self.tokens = tokens
        self.cost = cost
    }
}
