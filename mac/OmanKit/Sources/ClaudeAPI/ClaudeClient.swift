import Foundation
import OmanCore

public struct ClaudeClient: WritingService {
    public init() {}

    public func stream(_ request: WritingRequest, apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: WritingError.noOutput) }
    }

    public func validate(apiKey: String) async throws {}
}
