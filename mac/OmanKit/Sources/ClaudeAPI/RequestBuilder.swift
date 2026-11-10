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
            outputConfig: OutputConfig(effort: request.quality.effort),
            system: PromptBuilder.systemBlocks(for: request),
            messages: [UserMessage(content: PromptBuilder.userContent(for: request))],
            fallbacks: usesFallback ? "default" : nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        urlRequest.httpBody = try encoder.encode(body)
        return urlRequest
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
