import Foundation
import OmanCore

enum StreamEvent: Equatable {
    case text(String)
    case stopReason(String)
    case messageStop
    case failure(WritingError)
}

enum StreamEventParser {
    private struct RawEvent: Decodable {
        let type: String
        let delta: RawDelta?
        let error: APIErrorPayload?
    }

    private struct RawDelta: Decodable {
        let type: String?
        let text: String?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case stopReason = "stop_reason"
        }
    }

    /// Returns nil for lines and event types the client has no use for.
    static func event(fromLine line: String) -> StreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).drop { $0 == " " }
        guard let raw = try? JSONDecoder().decode(RawEvent.self, from: Data(payload.utf8)) else {
            return nil
        }

        switch raw.type {
        case "content_block_delta":
            guard raw.delta?.type == "text_delta", let text = raw.delta?.text, !text.isEmpty else {
                return nil
            }
            return .text(text)
        case "message_delta":
            return raw.delta?.stopReason.map(StreamEvent.stopReason)
        case "message_stop":
            return .messageStop
        case "error":
            return .failure(APIErrorMapper.error(forStreamError: raw.error))
        default:
            return nil
        }
    }
}
