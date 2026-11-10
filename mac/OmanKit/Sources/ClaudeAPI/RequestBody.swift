import Foundation

struct MessagesBody: Encodable {
    let model: String
    let maxTokens: Int
    let stream: Bool
    let outputConfig: OutputConfig
    let system: [SystemBlock]
    let messages: [UserMessage]
    let fallbacks: String?

    enum CodingKeys: String, CodingKey {
        case model, stream, system, messages, fallbacks
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }
}

struct OutputConfig: Encodable {
    let effort: String
}

struct SystemBlock: Encodable {
    let type = "text"
    let text: String
    let cacheControl: CacheControl?

    enum CodingKeys: String, CodingKey {
        case type, text
        case cacheControl = "cache_control"
    }
}

struct CacheControl: Encodable {
    let type = "ephemeral"
    let ttl: String
}

struct UserMessage: Encodable {
    let role = "user"
    let content: [ContentBlock]
}

enum ContentBlock: Encodable {
    case text(String)
    case jpegImage(base64: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, source
    }

    private struct ImageSource: Encodable {
        let type = "base64"
        let mediaType = "image/jpeg"
        let data: String

        enum CodingKeys: String, CodingKey {
            case type, data
            case mediaType = "media_type"
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .jpegImage(let base64):
            try container.encode("image", forKey: .type)
            try container.encode(ImageSource(data: base64), forKey: .source)
        }
    }
}
