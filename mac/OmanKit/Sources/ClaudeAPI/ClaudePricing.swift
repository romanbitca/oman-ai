import Foundation
import OmanCore

/// Anthropic's list prices in US dollars per million tokens, as published on 2026-11-11,
/// for the Claude API's default global routing.
enum ClaudePricing {
    struct Rates: Equatable {
        let input: Double
        let output: Double
        let cacheWrite5m: Double
        let cacheWrite1h: Double
        let cacheRead: Double
    }

    /// Haiku 5.5 charges its higher rates for a prompt over this many tokens, cached tokens included.
    static let haikuLongPromptThreshold = 100_000

    static func rates(for model: WritingModel, promptTokens: Int) -> Rates? {
        switch model {
        case .haiku:
            promptTokens > haikuLongPromptThreshold
                ? Rates(input: 0.50, output: 2.50, cacheWrite5m: 0.625, cacheWrite1h: 1, cacheRead: 0.05)
                : Rates(input: 0.10, output: 0.50, cacheWrite5m: 0.125, cacheWrite1h: 0.20, cacheRead: 0.01)
        case .sonnet:
            Rates(input: 2, output: 10, cacheWrite5m: 2.50, cacheWrite1h: 4, cacheRead: 0.10)
        case .opus:
            Rates(input: 4, output: 20, cacheWrite5m: 5, cacheWrite1h: 8, cacheRead: 0.20)
        case .appleOnDevice:
            nil
        }
    }

    /// `servedModel` is the model Anthropic says answered. A dated ID matches its model, and one this table
    /// doesn't know, such as a fallback model, is priced as the model that was asked for.
    static func cost(of tokens: TokenUsage, servedModel: String, requested: WritingModel) -> Double {
        let model = WritingModel.allCases.first { !$0.isLocal && servedModel.hasPrefix($0.rawValue) } ?? requested
        guard let rates = rates(for: model, promptTokens: tokens.promptTokens) else { return 0 }
        let dollarsPerMillion = Double(tokens.input) * rates.input
            + Double(tokens.output) * rates.output
            + Double(tokens.cacheRead) * rates.cacheRead
            + Double(tokens.cacheWrite5m) * rates.cacheWrite5m
            + Double(tokens.cacheWrite1h) * rates.cacheWrite1h
        return dollarsPerMillion / 1_000_000
    }
}
