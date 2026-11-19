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
    static func requestBody(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }; data.append(buffer, count: n)
        }
        return data
    }
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
        expect(refreshed.supportsCalendar, "New grants support direct Calendar conferences")
        let legacy = Credential(client: client, accessToken: "old", refreshToken: "old", expiresAt: Date())
        expect(!legacy.supportsCalendar, "Legacy Meet-only login requires reconnect")
        let pending = PendingConference.make()
        expect(PendingConference.id(from: pending.url) == pending.id, "Strict local pending-link roundtrip")
        expect(PendingConference.id(from: URL(string: "calendarmeet://pending/" + pending.id + "?extra=x")!) == nil, "No query injection")
        let bridgeURL = try BridgeReply(meetingURL: pending.url.absoluteString, error: nil).result()
        expect(bridgeURL == pending.url, "Bridge carries a pending request, never a fake Meet URL")
        rejects("Bridge refuses old detached Meet creation") { _ = try BridgeReply(meetingURL: "https://meet.google.com/abc-defg-hij", error: nil).result() }
        let restored = try JSONDecoder().decode(PendingConference.self, from: JSONEncoder().encode(pending))
        expect(restored == pending, "Pending request survives app restart")
        let calendar = CalendarConferenceAPI(google: api)
        var pageCalls = 0
        MockProtocol.handler = { request in
            pageCalls += 1
            let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            if pageCalls == 1 {
                return (200, #"{"nextPageToken":"page2","items":[{"id":"reader","accessRole":"reader","conferenceProperties":{"allowedConferenceSolutionTypes":["hangoutsMeet"]}}]}"#)
            }
            expect(q.contains(URLQueryItem(name: "pageToken", value: "page2")), "Calendar discovery follows pagination")
            return (200, #"{"items":[{"id":"writable","accessRole":"owner","conferenceProperties":{"allowedConferenceSolutionTypes":["hangoutsMeet"]}},{"id":"no-meet","accessRole":"owner","conferenceProperties":{"allowedConferenceSolutionTypes":[]}}]}"#)
        }
        let calendars = try await calendar.calendars(token: "access")
        expect(calendars.map(\.id) == ["writable"], "Only writable Meet-capable calendars are eligible")
        func eventJSON(_ fields: [String: Any] = [:]) throws -> String {
            var result: [String: Any] = ["id": "event1", "etag": "etag1", "status": "confirmed", "organizer": ["self": true],
                "description": "My notes " + pending.url.absoluteString + " keep this", "location": "Room 1"]
            result.merge(fields) { _, new in new }
            return String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!
        }
        let event = try JSONDecoder().decode(GoogleEvent.self, from: Data(try eventJSON().utf8))
        expect(event.carries(pending), "Exact random marker identifies saved event")
        let another = PendingConference.make()
        expect(!event.carries(another), "Different request cannot target this event")
        MockProtocol.handler = { request in
            expect(request.httpMethod == "PATCH", "Patch the existing event; no duplicate insert")
            expect(request.url!.path.contains("/calendars/team@example.com/events/event1"), "Use discovered calendar and event IDs")
            let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            expect(q.contains(URLQueryItem(name: "conferenceDataVersion", value: "1")), "Native conference data enabled")
            expect(q.contains(URLQueryItem(name: "sendUpdates", value: "all")), "Invitees receive real native conference link")
            expect(request.value(forHTTPHeaderField: "If-Match") == "etag1", "Concurrent edits protected by ETag")
            let body = try requestBody(request)
            let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            expect(Set(json.keys) == Set(["conferenceData"]), "Creation preserves notes, dates, invitees, location and all other fields")
            let conference = json["conferenceData"] as! [String: Any]
            let create = conference["createRequest"] as! [String: Any]
            expect(create["requestId"] as? String == pending.id, "Persisted request ID is stable for retries")
            expect((create["conferenceSolutionKey"] as? [String: String])?["type"] == "hangoutsMeet", "Google Calendar owns native Meet creation")
            return (200, try eventJSON(["conferenceData": ["createRequest": ["requestId": pending.id, "status": ["statusCode": "pending"]]]]))
        }
        let created = try await calendar.create(on: event, calendarID: "team@example.com", pending: pending, token: "access")
        expect(created.conferenceData?.createRequest?.status?.statusCode == "pending", "Handle asynchronous creation")
        MockProtocol.handler = { _ in fatalError("Idempotent resume must not issue another PATCH") }
        let resumed = try await calendar.create(on: created, calendarID: "team@example.com", pending: pending, token: "access")
        expect(resumed.id == event.id, "Resume existing conference creation")
        let nativeFields: [String: Any] = ["conferenceData": ["createRequest": ["requestId": pending.id, "status": ["statusCode": "success"]],
            "conferenceSolution": ["key": ["type": "hangoutsMeet"]],
            "entryPoints": [["entryPointType": "video", "uri": "https://meet.google.com/abc-defg-hij"]]]]
        let native = try JSONDecoder().decode(GoogleEvent.self, from: Data(try eventJSON(nativeFields).utf8))
        MockProtocol.handler = { request in
            expect(request.httpMethod == "PATCH", "Finalize the same existing event")
            expect(request.value(forHTTPHeaderField: "If-Match") == native.etag, "Finalize also protects concurrent edits")
            let json = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            expect(Set(json.keys) == Set(["description"]), "Finalization preserves native conference and every unrelated field")
            expect(json["description"] as? String == "My notes https://meet.google.com/abc-defg-hij keep this", "Replace only marker with this event's native URI")
            return (200, try eventJSON(nativeFields.merging(["description": "My notes https://meet.google.com/abc-defg-hij keep this"]) { _, value in value }))
        }
        let finished = try await calendar.finish(native, calendarID: "x", pending: pending, token: "a")
        expect(finished.meetURL == native.meetURL, "Native Meet conference survives finalization")
        MockProtocol.handler = { _ in fatalError("Already-finalized event must not be patched again") }
        _ = try await calendar.finish(finished, calendarID: "x", pending: pending, token: "a")
        do { _ = try await calendar.finish(created, calendarID: "x", pending: pending, token: "a"); fatalError("Unfinished conference finalized") } catch { checks += 1 }
        for fields: [String: Any] in [["organizer": ["self": false]], ["status": "cancelled"], ["recurringEventId": "parent"], ["description": "Unrelated notes"], ["conferenceData": ["entryPoints": []]]] {
            let unsafe = try JSONDecoder().decode(GoogleEvent.self, from: Data(try eventJSON(fields).utf8))
            do { _ = try await calendar.create(on: unsafe, calendarID: "x", pending: pending, token: "a"); fatalError("Unsafe event accepted") } catch { checks += 1 }
        }
        MockProtocol.handler = { request in
            expect(request.url!.absoluteString.contains("x%2Fy%23z"), "Calendar ID is encoded as a single path component")
            let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            expect(q.contains(URLQueryItem(name: "q", value: pending.id)), "Search only explicit pending request")
            expect(q.contains(URLQueryItem(name: "singleEvents", value: "false")), "Do not expand recurring series into multiple targets")
            return (200, "{\"items\":[" + (try eventJSON()) + "," + (try eventJSON(["id": "unrelated", "description": "unrelated"])) + "]}")
        }
        let matches = try await calendar.matches(pending, calendarID: "x/y#z", token: "a")
        expect(matches.count == 1 && matches[0].id == "event1", "Search results require exact marker verification")
        for status in [400, 401, 403, 404, 412, 429, 500] {
            MockProtocol.handler = { _ in (status, #"{"error":"DO_NOT_DISPLAY_SECRET"}"#) }
            do { _ = try await calendar.event(calendarID: "x", eventID: "y", token: "a"); fatalError("Expected HTTP error") }
            catch {
                expect(!error.localizedDescription.contains("DO_NOT_DISPLAY_SECRET"), "Response body not leaked")
                if status == 401 { expect(error is GoogleAuthorizationError, "Revoked login triggers disconnected status") }
                if status == 400 { expect(!(error is GoogleAuthorizationError), "Invalid event request does not falsely sign out") }
            }
        }
        MockProtocol.handler = { _ in (400, #"{"error":"invalid_grant"}"#) }
        do { _ = try await api.refresh(credential); fatalError("Revoked refresh accepted") }
        catch { expect(error is GoogleAuthorizationError, "Revoked refresh token triggers disconnected status") }
        let conference = VirtualConferenceProvider.conferenceDescriptor(url: pending.url)
        expect(conference.urlDescriptors.count == 1, "Exactly one pending entry point")
        expect(conference.urlDescriptors.first?.url == pending.url, "Marker reaches EventKit unchanged")
        expect(conference.title == nil && conference.urlDescriptors.first?.title == nil, "Use system conference presentation")
        expect(conference.conferenceDetails == nil, "No duplicate marker in notes")
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
        let returnedURL = try BridgeReply(meetingURL: pending.url.absoluteString, error: nil).result()
        expect(returnedURL == pending.url, "Bridge accepts pending Calendar link")
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
        let cancelledTask = Task { try await cancelled.code(state: "x") }
        cancelledTask.cancel()
        do { _ = try await cancelledTask.value; fatalError("Cancellation ignored") } catch { checks += 1 }
        print("Passed \(checks) checks: OAuth, HTTP errors, conference API, Calendar provider and loopback callback.")
    }
}
