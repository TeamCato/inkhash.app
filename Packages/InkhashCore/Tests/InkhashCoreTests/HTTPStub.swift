import Foundation
@testable import InkhashCore

/// Answers `URLSession` requests from a handler, so `APIClient` can be tested without a server.
/// Each session gets its own handler by id; tests run in parallel safely.
final class HTTPStub: URLProtocol, @unchecked Sendable {
    struct Recorded: Sendable {
        var method: String
        var path: String
        var query: String?
        var body: Data
        var headers: [String: String]
    }

    typealias Handler = @Sendable (Recorded) -> (status: Int, body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var recorded: [String: [Recorded]] = [:]
    private static let header = "X-Stub-ID"

    /// A client whose requests go to `handler`. `requests()` lists what it sent.
    static func client(workspace: String = APIClient.mainWorkspace, handler: @escaping Handler) -> (APIClient, () -> [Recorded]) {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPStub.self]
        configuration.httpAdditionalHeaders = [header: id]
        let session = URLSession(configuration: configuration)
        let client = APIClient(baseURL: URL(string: "http://stub.local")!, token: "tok", workspace: workspace, session: session)
        return (client, { lock.withLock { recorded[id] ?? [] } })
    }

    static func json(_ status: Int, _ text: String) -> (status: Int, body: Data) {
        (status, Data(text.utf8))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.header) ?? ""
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let entry = Recorded(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            query: request.url?.query,
            body: body,
            headers: request.allHTTPHeaderFields ?? [:]
        )
        let handler = Self.lock.withLock { () -> Handler? in
            Self.recorded[id, default: []].append(entry)
            return Self.handlers[id]
        }
        let answer: (status: Int, body: Data) = handler?(entry) ?? (status: 404, body: Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
