import Foundation
import Network

/// Ephemeral HTTP callback, bound only to IPv4 loopback; no LAN exposure.
final class Loopback: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CalendarMeet.oauth-loopback")
    private let listener: NWListener
    private var continuation: CheckedContinuation<String, Error>?
    private var ready: CheckedContinuation<String, Error>?
    private var expectedState = ""
    private var finished = false
    private var connections: [NWConnection] = []
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.ready = continuation
                self.listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard let port = self.listener.port else { return }
                        self.ready?.resume(returning: "http://127.0.0.1:\(port.rawValue)/oauth/callback")
                        self.ready = nil
                    case .failed(let error): self.finish(.failure(error))
                    default: break
                    }
                }
                self.listener.newConnectionHandler = { connection in
                    guard self.connections.count < 16 else { connection.cancel(); return }
                    self.connections.append(connection)
                    connection.start(queue: self.queue)
                    self.read(connection, accumulated: Data())
                    self.queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
                }
                self.listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 180) { self.finish(.failure(MeetError("Google sign-in timed out. Please try again."))) }
            }
        }
    }
    func code(state: String) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !self.finished else { continuation.resume(throwing: CancellationError()); return }
                    self.expectedState = state
                    self.continuation = continuation
                }
            }
        } onCancel: { self.cancel() }
    }
    func cancel() { queue.async { self.finish(.failure(CancellationError())) } }
    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
            var buffer = accumulated; buffer.append(data ?? Data())
            guard buffer.count <= 8192, error == nil else { connection.cancel(); return }
            if let header = String(data: buffer, encoding: .utf8), header.contains("\r\n\r\n") {
                let parts = header.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/oauth/callback?"),
                      self.continuation != nil else { self.respond(connection, status: "404 Not Found", body: "Not found."); return }
                do {
                    let code = try OAuth.callbackCode(target: String(parts[1]), expectedState: self.expectedState)
                    self.respond(connection, status: "200 OK", body: "Google connected. Return to Calendar Meet to finish setup.") {
                        self.finish(.success(code))
                    }
                } catch {
                    // Invalid/unsolicited callbacks cannot terminate the legitimate login attempt.
                    let validState = OAuth.stateMatches(target: String(parts[1]), expectedState: self.expectedState)
                    self.respond(connection, status: "400 Bad Request", body: "Sign-in was declined or could not be verified. Return to Calendar Meet and try again.") {
                        if validState { self.finish(.failure(error)) }
                    }
                }
            } else if !complete { self.read(connection, accumulated: buffer) }
            else { connection.cancel() }
        }
    }
    private func respond(_ connection: NWConnection, status: String, body: String, completion: (() -> Void)? = nil) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel(); completion?() })
    }
    private func finish(_ result: Result<String, Error>) {
        guard !finished else { return }; finished = true
        if let ready { ready.resume(throwing: MeetError("Could not open the local sign-in listener.")); self.ready = nil }
        continuation?.resume(with: result); continuation = nil
        listener.cancel(); connections.forEach { $0.cancel() }; connections.removeAll()
    }
}
