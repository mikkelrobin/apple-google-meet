import Foundation

/// An explicit, persisted request attached only when the user selects Google Meet.
/// It is a local app URL, never a fabricated Google Meet URL.
struct PendingConference: Codable, Equatable {
    let id: String
    let createdAt: Date
    var calendarID: String?
    var eventID: String?
    var url: URL { URL(string: "calendarmeet://pending/\(id)")! }
    static func make() -> PendingConference {
        PendingConference(id: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), createdAt: Date())
    }
    static func validID(_ id: String) -> Bool {
        id.count == 32 && id.allSatisfy { "0123456789abcdef".contains($0) }
    }
    static func id(from url: URL) -> String? {
        let id = String(url.path.dropFirst())
        guard url.scheme == "calendarmeet", url.host == "pending", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil, validID(id), url.path == "/" + id else { return nil }
        return id
    }
}

struct CalendarEntry: Decodable {
    let id: String
    let accessRole: String?
    struct Properties: Decodable { let allowedConferenceSolutionTypes: [String]? }
    let conferenceProperties: Properties?
    var supportsMeet: Bool {
        ["owner", "writer"].contains(accessRole ?? "") &&
        (conferenceProperties?.allowedConferenceSolutionTypes?.contains("hangoutsMeet") ?? false)
    }
}
struct GoogleEvent: Decodable {
    let id: String
    let etag: String
    let status: String?
    let description: String?
    let location: String?
    let recurringEventId: String?
    let eventType: String?
    struct Organizer: Decodable {
        let isSelf: Bool?
        enum CodingKeys: String, CodingKey { case isSelf = "self" }
    }
    let organizer: Organizer?
    struct Conference: Decodable {
        struct Request: Decodable {
            let requestId: String?
            struct Status: Decodable { let statusCode: String? }
            let status: Status?
        }
        struct Solution: Decodable {
            struct Key: Decodable { let type: String? }
            let key: Key?
        }
        struct Entry: Decodable { let entryPointType: String?; let uri: String? }
        let createRequest: Request?
        let conferenceSolution: Solution?
        let entryPoints: [Entry]?
    }
    let conferenceData: Conference?
    func carries(_ request: PendingConference) -> Bool {
        // Search is only a hint. Require our exact random marker on the fetched resource.
        [description, location].compactMap { $0 }.contains { $0.contains(request.url.absoluteString) }
    }
    var meetURL: URL? {
        guard conferenceData?.conferenceSolution?.key?.type == "hangoutsMeet",
              let text = conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri,
              let url = URL(string: text), url.scheme == "https", url.host == "meet.google.com",
              url.user == nil, url.password == nil, url.port == nil, url.path.count > 1 else { return nil }
        return url
    }
}

struct CalendarConferenceAPI {
    var google = GoogleAPI()
    struct Page<T: Decodable>: Decodable { let items: [T]?; let nextPageToken: String? }
    private func endpoint(_ components: [String], query: [String: String] = [:]) -> URL {
        // Encode each path segment independently: calendar IDs can contain @, / or #.
        var parts = URLComponents(string: "https://www.googleapis.com/calendar/v3")!
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        parts.percentEncodedPath += "/" + components.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        parts.queryItems = query.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        return parts.url!
    }
    private func request(_ path: [String], token: String, query: [String: String] = [:]) -> URLRequest {
        var r = URLRequest(url: endpoint(path, query: query))
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }
    func calendars(token: String) async throws -> [CalendarEntry] {
        var items: [CalendarEntry] = []; var page: String?
        repeat {
            var q = ["minAccessRole": "writer", "maxResults": "250", "showHidden": "true"]
            q["pageToken"] = page
            let result: Page<CalendarEntry> = try await google.send(request(["users", "me", "calendarList"], token: token, query: q))
            items += result.items ?? []; page = result.nextPageToken
        } while page != nil
        return items.filter(\.supportsMeet)
    }
    func matches(_ pending: PendingConference, calendarID: String, token: String) async throws -> [GoogleEvent] {
        var items: [GoogleEvent] = []; var page: String?
        repeat {
            var q = ["q": pending.id, "maxResults": "250", "showDeleted": "false", "singleEvents": "false"]
            q["pageToken"] = page
            let result: Page<GoogleEvent> = try await google.send(request(["calendars", calendarID, "events"], token: token, query: q))
            items += (result.items ?? []).filter { $0.carries(pending) && $0.status != "cancelled" }
            page = result.nextPageToken
        } while page != nil
        return items
    }
    func event(calendarID: String, eventID: String, token: String) async throws -> GoogleEvent {
        try await google.send(request(["calendars", calendarID, "events", eventID], token: token))
    }
    func create(on event: GoogleEvent, calendarID: String, pending: PendingConference, token: String) async throws -> GoogleEvent {
        guard event.carries(pending), event.status != "cancelled", event.organizer?.isSelf == true,
              event.recurringEventId == nil, event.eventType == nil || event.eventType == "default" else {
            throw MeetError("Google Meet can only be added to your own Google Calendar event. Recurring exceptions are not supported.")
        }
        // Keep other conferences and pending requests intact. A network retry must
        // reuse the persisted request ID rather than generate another conference.
        if let conference = event.conferenceData {
            if conference.createRequest?.requestId == pending.id { return event }
            throw MeetError("This event already has a video conference. Remove it before choosing Google Meet again.")
        }
        var r = request(["calendars", calendarID, "events", event.id], token: token,
                        query: ["conferenceDataVersion": "1", "sendUpdates": "all"])
        r.httpMethod = "PATCH"
        r.setValue(event.etag, forHTTPHeaderField: "If-Match")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Keep the marker until Google has returned the event's native Meet URI.
        r.httpBody = try JSONSerialization.data(withJSONObject: ["conferenceData": ["createRequest": [
            "requestId": pending.id, "conferenceSolutionKey": ["type": "hangoutsMeet"]]]])
        return try await google.send(r)
    }
    func finish(_ event: GoogleEvent, calendarID: String, pending: PendingConference, token: String) async throws -> GoogleEvent {
        guard let link = event.meetURL, event.conferenceData?.createRequest?.requestId == pending.id else {
            throw MeetError("Google has not finished creating this event's own Meet conference.")
        }
        // Apple can retain its original conference record after the marker is
        // removed. Replace its URI with this SAME event's native Meet URI instead.
        // Other note text and the exported conference block remain unchanged.
        var fields: [String: String] = [:]
        if let text = event.description, text.contains(pending.url.absoluteString) {
            fields["description"] = text.replacingOccurrences(of: pending.url.absoluteString, with: link.absoluteString)
        }
        if let text = event.location, text.contains(pending.url.absoluteString) {
            fields["location"] = text.replacingOccurrences(of: pending.url.absoluteString, with: link.absoluteString)
        }
        guard !fields.isEmpty else { return event }
        var r = request(["calendars", calendarID, "events", event.id], token: token,
                        query: ["conferenceDataVersion": "1", "sendUpdates": "all"])
        r.httpMethod = "PATCH"; r.setValue(event.etag, forHTTPHeaderField: "If-Match")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: fields)
        return try await google.send(r)
    }
}
