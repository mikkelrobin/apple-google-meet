import Foundation
import EventKit

final class MockProtocol: URLProtocol {
    static var handler: (URLRequest) throws -> (Int, String) = { _ in (500, "{}") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, body) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
struct Tests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); checks += 1
    }
    static func rejects(_ label: String, _ action: () throws -> Void) {
        do { try action(); fatalError("Expected rejection: \(label)") } catch { checks += 1 }
    }
    static func tryBridgeCallback(_ request: URL) -> URL? { try? BridgeRequest.callback(from: request) }
    static func main() async throws {
        expect(OAuth.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "RFC 7636 PKCE vector")
        let random = try OAuth.random(); expect(random.count == 43, "Secure random verifier length")
        expect(String(data: OAuth.form(["code": "a+b &=é"]), encoding: .utf8) == "code=a%2Bb%20%26%3D%C3%A9", "Form encoding")
        let client = try OAuthClient.parse(Data(#"{"installed":{"client_id":"test.apps.googleusercontent.com","client_secret":"desktop-public"}}"#.utf8))
        rejects("web client") { _ = try OAuthClient.parse(Data(#"{"web":{"client_id":"x"}}"#.utf8)) }
        let auth = URLComponents(url: OAuth.authorizationURL(client: client, redirect: "http://127.0.0.1:1234/oauth/callback", verifier: random, state: "nonce"), resolvingAgainstBaseURL: false)!
        expect(auth.host == "accounts.google.com", "System browser Google endpoint")
        expect(auth.queryItems!.first { $0.name == "scope" }?.value == OAuth.scope, "Least privilege scope")
        expect(auth.queryItems!.first { $0.name == "code_challenge_method" }?.value == "S256", "PKCE mandatory")
        let code = try OAuth.callbackCode(target: "/oauth/callback?state=nonce&code=a%2Bb", expectedState: "nonce")
        expect(code == "a+b", "Callback decode")
        rejects("forged state") { _ = try OAuth.callbackCode(target: "/oauth/callback?state=wrong&code=x", expectedState: "nonce") }
        rejects("duplicate state") { _ = try OAuth.callbackCode(target: "/oauth/callback?state=nonce&state=nonce&code=x", expectedState: "nonce") }
        rejects("wrong path") { _ = try OAuth.callbackCode(target: "/other?state=nonce&code=x", expectedState: "nonce") }
        rejects("denied consent") { _ = try OAuth.callbackCode(target: "/oauth/callback?state=nonce&error=access_denied", expectedState: "nonce") }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let api = GoogleAPI(session: URLSession(configuration: config))
        MockProtocol.handler = { request in
            expect(request.url!.absoluteString == "https://oauth2.googleapis.com/token", "Token endpoint")
            var bodyData = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bodyData.append(buffer, count: count) }
            }
            let body = String(data: bodyData, encoding: .utf8) ?? ""
            expect(body.contains("code_verifier="), "Token exchange includes PKCE")
            return (200, #"{"access_token":"access","refresh_token":"refresh","expires_in":3600}"#)
        }
        let credential = try await api.exchange(code: "code", client: client, redirect: "http://127.0.0.1:1234/oauth/callback", verifier: random)
        expect(credential.refreshToken == "refresh", "Offline access saved")
        MockProtocol.handler = { _ in (200, #"{"access_token":"next","expires_in":3600}"#) }
        let refreshed = try await api.refresh(credential)
        expect(refreshed.refreshToken == "refresh", "Refresh token preserved when Google omits it")
        MockProtocol.handler = { request in
            expect(request.httpMethod == "POST", "Create uses POST")
            expect(request.url!.absoluteString == "https://meet.googleapis.com/v2/spaces", "Meet spaces endpoint")
            expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access", "Bearer authorization")
            return (200, #"{"meetingUri":"https://meet.google.com/abc-defg-hij"}"#)
        }
        let link = try await api.createSpace(accessToken: "access")
        expect(link.host == "meet.google.com", "Valid meeting URL")
        MockProtocol.handler = { _ in (200, #"{"meetingUri":"https://evil.example/"}"#) }
        do { _ = try await api.createSpace(accessToken: "access"); fatalError("Unsafe URL") } catch { checks += 1 }
        for status in [400, 401, 403, 429, 500] {
            MockProtocol.handler = { _ in (status, #"{"error":"DO_NOT_DISPLAY_SECRET"}"#) }
            do { _ = try await api.createSpace(accessToken: "access"); fatalError("Expected HTTP error") }
            catch {
                expect(!error.localizedDescription.contains("DO_NOT_DISPLAY_SECRET"), "Response body not leaked")
                if status == 401 { expect(error is GoogleAuthorizationError, "Revoked login is classified for red status") }
            }
        }
        expect(credential.supportsMeet, "New login includes Meet scope")
        let calendarOnly = Credential(client: client, accessToken: "test", refreshToken: "test", expiresAt: .distantFuture,
            scopes: ["https://www.googleapis.com/auth/calendar.events"])
        expect(!calendarOnly.supportsMeet, "Calendar-only login must reconnect for Meet")
        let descriptor = VirtualConferenceProvider.conferenceDescriptor(url: link)
        expect(descriptor.urlDescriptors.count == 1 && descriptor.urlDescriptors.first?.url == link, "Actual Meet URI is ready before provider returns")
        expect(descriptor.conferenceDetails == nil, "No duplicate meeting text")
        rejects("No temporary app link can escape to an invitation") {
            _ = try BridgeReply(meetingURL: "calendarmeet://pending/abc", error: nil).result()
        }
        let provider = VirtualConferenceProvider()
        let rooms = try await provider.fetchAvailableRoomTypes()
        expect(rooms.count == 1 && rooms[0].title == "Google Meet", "Single Calendar menu option")
        do { _ = try await provider.fetchVirtualConference(identifier: "unknown"); fatalError("Unknown room accepted") } catch { checks += 1 }
        do { _ = try await provider.fetchVirtualConference(identifier: "google-meet-new"); fatalError("Provider must reject a missing containing app") } catch { checks += 1 }
        let bridge = try BridgeListener()
        let callback = try await bridge.start(timeout: 3)
        let waiting = await BridgeRequest.isWaiting(callback)
        expect(waiting, "Bridge preflight accepts active callback")
        let request = BridgeRequest.url(callback: callback)
        expect(tryBridgeCallback(request) == callback, "Bridge request roundtrip")
        let badCallbacks = ["http://example.com:1234/return/" + random,
                            "http://127.0.0.1:80/return/" + random,
                            "http://127.0.0.1:1234/return/short",
                            "http://127.0.0.1:1234/return/" + random + "?extra=x",
                            "http://user@127.0.0.1:1234/return/" + random]
        for text in badCallbacks {
            rejects("Bridge rejects unsafe callback") { _ = try BridgeRequest.callback(from: BridgeRequest.url(callback: URL(string: text)!)) }
        }
        let bridgeWait = Task { try await bridge.response() }
        var badRequest = URLRequest(url: callback.deletingLastPathComponent().appendingPathComponent("wrong"))
        badRequest.httpMethod = "POST"; badRequest.httpBody = Data("{}".utf8)
        let (_, badResponse) = try await URLSession.shared.data(for: badRequest)
        expect((badResponse as! HTTPURLResponse).statusCode == 404, "Bridge ignores wrong capability")
        try await BridgeRequest.reply(BridgeReply(meetingURL: nil, error: "Not connected"), to: callback)
        let bridgeReply = try await bridgeWait.value
        expect(bridgeReply.error == "Not connected", "Bridge carries errors without credentials")
        let expired = await BridgeRequest.isWaiting(callback)
        expect(!expired, "Bridge ignores expired callbacks")
        rejects("Bridge validates returned Meet link") { _ = try BridgeReply(meetingURL: "https://evil.example/", error: nil).result() }
        let returnedURL = try BridgeReply(meetingURL: "https://meet.google.com/abc-defg-hij", error: nil).result()
        expect(returnedURL.host == "meet.google.com", "Bridge accepts a valid Meet link")
        let timed = try BridgeListener(); _ = try await timed.start(timeout: 0.05)
        do { _ = try await timed.response(); fatalError("Bridge timeout ignored") } catch { checks += 1 }
        let cancelledBridge = try BridgeListener(); _ = try await cancelledBridge.start()
        let cancelledReply = Task { try await cancelledBridge.response() }; cancelledReply.cancel()
        do { _ = try await cancelledReply.value; fatalError("Bridge cancellation ignored") } catch { checks += 1 }
        // Real loopback exchange, including ignored CSRF attempt and fragmented HTTP handled by the server.
        let loopback = try Loopback()
        let redirect = try await loopback.start()
        let wait = Task { try await loopback.code(state: "nonce") }
        await Task.yield()
        let (_, bad) = try await URLSession.shared.data(from: URL(string: redirect + "?state=forged&code=bad")!)
        expect((bad as! HTTPURLResponse).statusCode == 400, "Loopback rejects CSRF")
        let (_, good) = try await URLSession.shared.data(from: URL(string: redirect + "?state=nonce&code=good")!)
        expect((good as! HTTPURLResponse).statusCode == 200, "Loopback accepts valid request")
        let received = try await wait.value; expect(received == "good", "Loopback returns authorization code")
        let denied = try Loopback(); let deniedRedirect = try await denied.start()
        let deniedWait = Task { try await denied.code(state: "nonce") }
        await Task.yield()
        _ = try await URLSession.shared.data(from: URL(string: deniedRedirect + "?state=nonce&error=access_denied")!)
        do { _ = try await deniedWait.value; fatalError("Denied consent ignored") } catch { checks += 1 }
        let cancelled = try Loopback(); _ = try await cancelled.start()
        let pending = Task { try await cancelled.code(state: "x") }
        pending.cancel()
        do { _ = try await pending.value; fatalError("Cancellation ignored") } catch { checks += 1 }
        print("Passed \(checks) checks: OAuth, HTTP errors, conference API, Calendar provider and loopback callback.")
    }
}
