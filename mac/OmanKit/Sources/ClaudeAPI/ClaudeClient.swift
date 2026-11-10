import Foundation
import OmanCore

public struct ClaudeClient: WritingService {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.urlCache = nil
        self.init(session: URLSession(configuration: configuration))
    }

    init(session: URLSession) {
        self.session = session
    }

    public func stream(_ request: WritingRequest, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [session] in
                do {
                    try await Self.run(request, apiKey: apiKey, session: session) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    if let failure = Self.writingError(for: error) {
                        continuation.finish(throwing: failure)
                    } else {
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func validate(apiKey: String) async throws {
        do {
            let urlRequest = try RequestBuilder.validationRequest(apiKey: apiKey)
            let (body, response) = try await session.data(for: urlRequest)
            let http = try Self.httpResponse(from: response)
            guard (200..<300).contains(http.statusCode) else {
                throw APIErrorMapper.error(for: http, body: body)
            }
        } catch {
            throw Self.writingError(for: error) ?? CancellationError()
        }
    }

    public func unavailableReason(for model: WritingModel) -> String? { nil }

    private static func run(
        _ request: WritingRequest,
        apiKey: String,
        session: URLSession,
        yield: (String) -> Void
    ) async throws {
        let urlRequest = try RequestBuilder.messagesRequest(for: request, apiKey: apiKey)
        let (bytes, response) = try await session.bytes(for: urlRequest)
        let http = try httpResponse(from: response)
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
            }
            throw APIErrorMapper.error(for: http, body: body)
        }

        var yieldedText = false
        var stopReason: String?
        var line: [UInt8] = []

        // AsyncBytes.lines also splits on U+2028, U+2029 and U+0085, which can sit unescaped inside JSON strings.
        lineLoop: for try await byte in bytes {
            guard byte == UInt8(ascii: "\n") else {
                line.append(byte)
                continue
            }
            defer { line.removeAll(keepingCapacity: true) }

            switch StreamEventParser.event(fromLine: String(decoding: line, as: UTF8.self)) {
            case .text(let delta):
                yieldedText = true
                yield(delta)
            case .stopReason(let reason):
                stopReason = reason
            case .failure(let error):
                throw error
            case .messageStop:
                break lineLoop
            case nil:
                continue
            }
        }

        try Task.checkCancellation()

        switch stopReason {
        case "end_turn", "stop_sequence":
            break
        case "refusal":
            throw WritingError.refused
        default:
            // max_tokens, a reason this client doesn't know, or a response that ended before saying why it stopped.
            // In each case the text so far is not a whole answer.
            throw WritingError.truncated
        }
        if !yieldedText {
            throw WritingError.noOutput
        }
    }

    private static func httpResponse(from response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw WritingError.network("Received an unexpected response.")
        }
        return http
    }

    /// Returns nil for cancellation, which is not a failure.
    private static func writingError(for error: any Error) -> WritingError? {
        switch error {
        case is CancellationError:
            return nil
        case let error as WritingError:
            return error
        case let error as URLError where error.code == .cancelled:
            return nil
        default:
            return .network(error.localizedDescription)
        }
    }
}
