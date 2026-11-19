import Foundation
import Network

struct BridgeReply: Codable {
    let meetingURL: String?
    let error: String?
    func result() throws -> URL {
        if let error { throw MeetError(error) }
        guard let text = meetingURL, let url = URL(string: text), PendingConference.id(from: url) != nil else {
            throw MeetError("The app returned an invalid Calendar setup link.")
        }
        return url
    }
}

private final class LocalOnlySession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum BridgeRequest {
    private static let localSession = URLSession(configuration: .ephemeral, delegate: LocalOnlySession(), delegateQueue: nil)
    static func isWaiting(_ callback: URL) async -> Bool {
        guard (try? self.callback(from: url(callback: callback))) != nil else { return false }
        var request = URLRequest(url: callback); request.httpMethod = "HEAD"; request.timeoutInterval = 3
        guard let (_, response) = try? await localSession.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
    static func callback(from request: URL) throws -> URL {
        guard let parts = URLComponents(url: request, resolvingAgainstBaseURL: false),
              parts.scheme == "calendarmeet", parts.host == "conference", parts.path.isEmpty else {
            throw MeetError("Invalid Calendar request.")
        }
        let values = (parts.queryItems ?? []).filter { $0.name == "callback" }
        guard values.count == 1, let text = values.first?.value, let callback = URL(string: text),
              callback.scheme == "http", callback.host == "127.0.0.1", callback.user == nil,
              callback.password == nil, let port = callback.port, (1024...65535).contains(port),
              callback.query == nil, callback.fragment == nil,
              callback.path.hasPrefix("/return/"), callback.path.dropFirst(8).count == 43,
              callback.path.dropFirst(8).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw MeetError("Invalid local Calendar callback.")
        }
        return callback
    }
    static func url(callback: URL) -> URL {
        var parts = URLComponents(); parts.scheme = "calendarmeet"; parts.host = "conference"
        parts.queryItems = [URLQueryItem(name: "callback", value: callback.absoluteString)]
        return parts.url!
    }
    static func reply(_ reply: BridgeReply, to callback: URL, session: URLSession? = nil) async throws {
        // The callback must pass the same validation even for internal callers.
        _ = try self.callback(from: url(callback: callback))
        var request = URLRequest(url: callback); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(reply); request.timeoutInterval = 5
        let (_, response) = try await (session ?? localSession).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MeetError("Calendar stopped waiting. Select Google Meet again.") }
    }
}

/// One-use loopback response channel. Carries a meeting link or error, never OAuth credentials.
final class BridgeListener: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CalendarMeet.conference-bridge")
    private let listener: NWListener
    private let path: String
    private var startWait: CheckedContinuation<URL, Error>?
    private var replyWait: CheckedContinuation<BridgeReply, Error>?
    private var outcome: Result<BridgeReply, Error>?
    private var connections: [NWConnection] = []
    init() throws {
        path = "/return/" + (try OAuth.random())
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
    }
    func start(timeout: TimeInterval = 55) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.startWait = continuation
                self.listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if let port = self.listener.port {
                            self.startWait?.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)\(self.path)")!)
                            self.startWait = nil
                        }
                    case .failed(let error): self.finish(.failure(error))
                    default: break
                    }
                }
                self.listener.newConnectionHandler = { connection in
                    guard self.connections.count < 16 else { connection.cancel(); return }
                    self.connections.append(connection); connection.start(queue: self.queue)
                    self.read(connection, data: Data())
                    self.queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
                }
                self.listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(MeetError("Calendar Meet timed out. Open the app, connect Google, and select Google Meet again.")))
                }
            }
        }
    }
    func response() async throws -> BridgeReply {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let outcome = self.outcome { continuation.resume(with: outcome) }
                    else { self.replyWait = continuation }
                }
            }
        } onCancel: { self.cancel() }
    }
    func cancel() { queue.async { self.finish(.failure(CancellationError())) } }
    private func read(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { chunk, _, complete, error in
            var bytes = data; bytes.append(chunk ?? Data())
            guard error == nil, bytes.count <= 8192 else { connection.cancel(); return }
            if let end = bytes.range(of: Data("\r\n\r\n".utf8)),
               let headers = String(data: bytes[..<end.lowerBound], encoding: .utf8) {
                let lines = headers.components(separatedBy: "\r\n")
                let request = lines[0].split(separator: " ")
                if request.count == 3, request[0] == "HEAD", request[1] == Substring(self.path) {
                    self.respond(connection, status: "200 OK"); return
                }
                guard request.count == 3, request[0] == "POST", request[1] == Substring(self.path) else {
                    self.respond(connection, status: "404 Not Found"); return
                }
                let lengths = lines.dropFirst().filter { $0.lowercased().hasPrefix("content-length:") }
                guard lengths.count == 1, let length = Int(lengths[0].dropFirst(15).trimmingCharacters(in: .whitespaces)),
                      length > 0, length <= 4096 else { self.respond(connection, status: "400 Bad Request"); return }
                let body = bytes[end.upperBound...]
                if body.count >= length {
                    do {
                        guard body.count == length else { throw MeetError("Unexpected callback payload.") }
                        let reply = try JSONDecoder().decode(BridgeReply.self, from: Data(body))
                        guard (reply.meetingURL == nil) != (reply.error == nil) else { throw MeetError("Invalid callback payload.") }
                        self.respond(connection, status: "200 OK") { self.finish(.success(reply)) }
                    } catch { self.respond(connection, status: "400 Bad Request") }
                } else if !complete { self.read(connection, data: bytes) }
                else { connection.cancel() }
            } else if !complete { self.read(connection, data: bytes) }
            else { connection.cancel() }
        }
    }
    private func respond(_ connection: NWConnection, status: String, completion: (() -> Void)? = nil) {
        connection.send(content: Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in
            connection.cancel(); completion?()
        })
    }
    private func finish(_ result: Result<BridgeReply, Error>) {
        guard outcome == nil else { return }; outcome = result
        if let startWait { startWait.resume(throwing: MeetError("Could not open the Calendar callback.")); self.startWait = nil }
        replyWait?.resume(with: result); replyWait = nil
        listener.cancel(); connections.forEach { $0.cancel() }; connections.removeAll()
    }
}
