import Foundation

struct StubReply: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
    var finishes = true
    var failure: URLError?
}

struct CapturedRequest: Sendable {
    let request: URLRequest
    let body: Data
}

final class StubStore: @unchecked Sendable {
    static let shared = StubStore()

    private let lock = NSLock()
    private var currentReply = StubReply()
    private var capturedRequests: [CapturedRequest] = []
    private var didStop = false

    func reset(reply: StubReply) {
        lock.withLock {
            currentReply = reply
            capturedRequests = []
            didStop = false
        }
    }

    var reply: StubReply { lock.withLock { currentReply } }
    var captured: [CapturedRequest] { lock.withLock { capturedRequests } }
    var stopped: Bool { lock.withLock { didStop } }

    func record(_ request: CapturedRequest) {
        lock.withLock { capturedRequests.append(request) }
    }

    func markStopped() {
        lock.withLock { didStop = true }
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubStore.shared.record(CapturedRequest(request: request, body: Self.body(of: request)))
        let reply = StubStore.shared.reply

        if let failure = reply.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }

        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: reply.headers
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty {
            client?.urlProtocol(self, didLoad: reply.body)
        }
        if reply.finishes {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        StubStore.shared.markStopped()
    }

    /// URLSession moves httpBody into httpBodyStream before a URLProtocol sees the request.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }
}
