import Foundation
import OmanCore

enum RequestBuilder {
    private static let apiVersion = "2026-10-21"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    static func messagesRequest(for request: WritingRequest, apiKey: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: try endpoint("https://api.anthropic.com/v1/messages"))
        urlRequest.httpMethod = "POST"
        applyAuthentication(to: &urlRequest, apiKey: apiKey)
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")

        let usesFallback = supportsServerSideFallback(request.model)
        if usesFallback {
            urlRequest.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }

        let body = MessagesBody(
            model: request.model.rawValue,
            maxTokens: 16000,
            stream: true,
            outputConfig: OutputConfig(effort: effort(for: request)),
            system: PromptBuilder.systemBlocks(for: request),
            messages: [UserMessage(content: PromptBuilder.userContent(for: request, code: PromptBuilder.makeTagCode()))],
            fallbacks: usesFallback ? "default" : nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        urlRequest.httpBody = try encoder.encode(body)
        return urlRequest
    }

    /// Proofread, and anything that carries the person's own instruction, ask Haiku and Sonnet for their highest
    /// effort whatever quality is set. At lower effort they start writing without thinking. Tried on eight kinds
    /// of text, Haiku then got about one proofread in four wrong, and an action asking for five words gave seven
    /// to twelve; thinking first it got no proofread wrong and one action in thirty, for about a second more.
    /// Opus thinks at every effort.
    static func effort(for request: WritingRequest) -> String {
        guard takesCare(request) else { return request.quality.effort }
        switch request.model {
        case .haiku, .sonnet: return WritingQuality.best.effort
        case .opus, .appleOnDevice: return request.quality.effort
        }
    }

    private static func takesCare(_ request: WritingRequest) -> Bool {
        switch request.task {
        case .proofread, .custom: true
        case .rewrite(_, let instruction): instruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .compose, .explain: false
        }
    }

    static func validationRequest(apiKey: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: try endpoint("https://api.anthropic.com/v1/models?limit=1"))
        urlRequest.httpMethod = "GET"
        applyAuthentication(to: &urlRequest, apiKey: apiKey)
        return urlRequest
    }

    private static func supportsServerSideFallback(_ model: WritingModel) -> Bool {
        switch model {
        case .sonnet, .opus: true
        case .haiku, .appleOnDevice: false
        }
    }

    private static func applyAuthentication(to urlRequest: inout URLRequest, apiKey: String) {
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
    }

    private static func endpoint(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw WritingError.network("Invalid endpoint address.")
        }
        return url
    }
}
