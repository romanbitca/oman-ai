import Foundation
import OmanCore

/// Token counts as one stream event reports them. A field the event leaves out is nil.
struct UsageReport: Equatable {
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var cacheWrite5m: Int?
    var cacheWrite1h: Int?
}

enum StreamEvent: Equatable {
    case started(model: String?, usage: UsageReport?)
    case text(String)
    case delta(stopReason: String?, usage: UsageReport?)
    case messageStop
    case failure(WritingError)
}

enum StreamEventParser {
    private struct RawEvent: Decodable {
        let type: String
        let message: RawMessage?
        let delta: RawDelta?
        let usage: RawUsage?
        let error: APIErrorPayload?

        enum CodingKeys: String, CodingKey {
            case type, message, delta, usage, error
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            delta = try container.decodeIfPresent(RawDelta.self, forKey: .delta)
            error = try container.decodeIfPresent(APIErrorPayload.self, forKey: .error)
            // Token counts only feed the spending page, so a shape this client doesn't expect
            // must not cost the event its stop reason.
            message = try? container.decodeIfPresent(RawMessage.self, forKey: .message)
            usage = try? container.decodeIfPresent(RawUsage.self, forKey: .usage)
        }
    }

    private struct RawMessage: Decodable {
        let model: String?
        let usage: RawUsage?

        enum CodingKeys: String, CodingKey {
            case model, usage
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            model = try? container.decodeIfPresent(String.self, forKey: .model)
            usage = try? container.decodeIfPresent(RawUsage.self, forKey: .usage)
        }
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

    private struct RawUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheCreation: RawCacheCreation?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheCreation = "cache_creation"
        }

        var report: UsageReport {
            UsageReport(
                input: inputTokens,
                output: outputTokens,
                cacheRead: cacheReadInputTokens,
                cacheWrite: cacheCreationInputTokens,
                cacheWrite5m: cacheCreation?.ephemeral5m,
                cacheWrite1h: cacheCreation?.ephemeral1h
            )
        }
    }

    private struct RawCacheCreation: Decodable {
        let ephemeral5m: Int?
        let ephemeral1h: Int?

        enum CodingKeys: String, CodingKey {
            case ephemeral5m = "ephemeral_5m_input_tokens"
            case ephemeral1h = "ephemeral_1h_input_tokens"
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
        case "message_start":
            return .started(model: raw.message?.model, usage: raw.message?.usage?.report)
        case "content_block_delta":
            guard raw.delta?.type == "text_delta", let text = raw.delta?.text, !text.isEmpty else {
                return nil
            }
            return .text(text)
        case "message_delta":
            let stopReason = raw.delta?.stopReason
            let usage = raw.usage?.report
            guard stopReason != nil || usage != nil else { return nil }
            return .delta(stopReason: stopReason, usage: usage)
        case "message_stop":
            return .messageStop
        case "error":
            return .failure(APIErrorMapper.error(forStreamError: raw.error))
        default:
            return nil
        }
    }
}

/// Adds up what a stream reports about its tokens. The counts in `message_delta` are running totals,
/// so a field it gives replaces the one from `message_start`.
struct UsageMeter {
    private(set) var model: String?
    private var report = UsageReport()
    private var hasReport = false

    mutating func start(model: String?, usage: UsageReport?) {
        if let model { self.model = model }
        if let usage { merge(usage) }
    }

    mutating func merge(_ usage: UsageReport) {
        hasReport = true
        report.input = usage.input ?? report.input
        report.output = usage.output ?? report.output
        report.cacheRead = usage.cacheRead ?? report.cacheRead
        report.cacheWrite = usage.cacheWrite ?? report.cacheWrite
        report.cacheWrite5m = usage.cacheWrite5m ?? report.cacheWrite5m
        report.cacheWrite1h = usage.cacheWrite1h ?? report.cacheWrite1h
    }

    /// Nil until the stream has reported anything.
    var tokens: TokenUsage? {
        guard hasReport else { return nil }
        let hasBreakdown = report.cacheWrite5m != nil || report.cacheWrite1h != nil
        // Without a breakdown the writes can only be the style block's, which is cached for an hour.
        return TokenUsage(
            input: report.input ?? 0,
            output: report.output ?? 0,
            cacheRead: report.cacheRead ?? 0,
            cacheWrite5m: hasBreakdown ? report.cacheWrite5m ?? 0 : 0,
            cacheWrite1h: hasBreakdown ? report.cacheWrite1h ?? 0 : report.cacheWrite ?? 0
        )
    }
}
