import Foundation
import OmanCore

struct APIErrorPayload: Decodable {
    let type: String?
    let message: String?
}

enum APIErrorMapper {
    private struct ErrorEnvelope: Decodable {
        let error: APIErrorPayload?
    }

    static func error(for response: HTTPURLResponse, body: Data) -> WritingError {
        let payload = (try? JSONDecoder().decode(ErrorEnvelope.self, from: body))?.error
        let message = payload?.message ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)

        switch response.statusCode {
        case 401:
            return .invalidAPIKey
        case 402:
            return .billing
        case 403:
            return .accessDenied(message)
        case 404:
            return .modelUnavailable
        case 413:
            return .requestTooLarge
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "retry-after")
                .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return .rateLimited(retryAfterSeconds: retryAfter)
        case 529:
            return .overloaded
        default:
            return .server(status: response.statusCode, message: message)
        }
    }

    static func error(forStreamError payload: APIErrorPayload?) -> WritingError {
        switch payload?.type {
        case "overloaded_error":
            return .overloaded
        case "rate_limit_error":
            return .rateLimited(retryAfterSeconds: nil)
        default:
            return .server(status: 0, message: payload?.message ?? "The response stream failed.")
        }
    }
}
