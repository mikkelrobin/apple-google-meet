import Foundation
import CryptoKit

struct MeetError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct OAuthClient: Codable, Equatable {
    let clientID: String
    let clientSecret: String
    static func parse(_ data: Data) throws -> OAuthClient {
        struct Export: Decodable {
            struct Installed: Decodable { let client_id: String; let client_secret: String }
            let installed: Installed
        }
        let export: Export
        do { export = try JSONDecoder().decode(Export.self, from: data) }
        catch { throw MeetError("Choose Google's downloaded Desktop app client JSON (not a Web client).") }
        guard export.installed.client_id.hasSuffix(".apps.googleusercontent.com"),
              !export.installed.client_secret.isEmpty else { throw MeetError("Invalid Google Desktop client file.") }
        return OAuthClient(clientID: export.installed.client_id, clientSecret: export.installed.client_secret)
    }
}

struct Credential: Codable {
    let client: OAuthClient
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]? = nil
    var supportsCalendar: Bool { Set(OAuth.scopes).isSubset(of: Set(scopes ?? [])) }
}

enum OAuth {
    static let scopes = ["https://www.googleapis.com/auth/calendar.events",
                         "https://www.googleapis.com/auth/calendar.calendarlist.readonly"]
    static let scope = scopes.joined(separator: " ")
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MeetError("Could not create a secure login request.")
        }
        return Data(bytes).base64URL
    }
    static func challenge(_ verifier: String) -> String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
    static func authorizationURL(client: OAuthClient, redirect: String, verifier: String, state: String) -> URL {
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = ["client_id": client.clientID, "redirect_uri": redirect, "response_type": "code",
                          "scope": scope, "code_challenge": challenge(verifier), "code_challenge_method": "S256",
                          "state": state, "access_type": "offline", "prompt": "consent"].map(URLQueryItem.init)
        return url.url!
    }
    static func stateMatches(target: String, expectedState: String) -> Bool {
        guard let url = URLComponents(string: "http://127.0.0.1\(target)"), url.path == "/oauth/callback" else { return false }
        let states = (url.queryItems ?? []).filter { $0.name == "state" }
        return states.count == 1 && states[0].value == expectedState
    }
    static func callbackCode(target: String, expectedState: String) throws -> String {
        guard let url = URLComponents(string: "http://127.0.0.1\(target)"), url.path == "/oauth/callback" else {
            throw MeetError("Unexpected login callback path.")
        }
        let items = url.queryItems ?? []
        func unique(_ key: String) -> String? {
            let matches = items.filter { $0.name == key }
            return matches.count == 1 ? matches[0].value : nil
        }
        guard unique("state") == expectedState else { throw MeetError("Login security check failed. Please try again.") }
        if unique("error") != nil { throw MeetError("Google sign-in was declined. Please try again when ready.") }
        guard let code = unique("code"), !code.isEmpty else { throw MeetError("Google returned no authorization code.") }
        return code
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

struct GoogleAPI {
    var session: URLSession = .shared
    struct Token: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double; let scope: String? }
    func token(_ fields: [String: String]) async throws -> Token {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuth.form(fields)
        return try await send(request)
    }
    func exchange(code: String, client: OAuthClient, redirect: String, verifier: String) async throws -> Credential {
        let response = try await token(["grant_type": "authorization_code", "code": code, "client_id": client.clientID,
                                        "client_secret": client.clientSecret, "redirect_uri": redirect, "code_verifier": verifier])
        guard let refresh = response.refresh_token, !refresh.isEmpty else { throw MeetError("Google did not issue offline access. Reconnect and grant access.") }
        if let scopes = response.scope, !Set(OAuth.scopes).isSubset(of: Set(scopes.split(separator: " ").map(String.init))) {
            throw MeetError("Calendar permission was not granted. Reconnect and allow calendar access.")
        }
        return Credential(client: client, accessToken: response.access_token, refreshToken: refresh,
                          expiresAt: Date().addingTimeInterval(response.expires_in),
                          scopes: response.scope?.split(separator: " ").map(String.init) ?? OAuth.scopes)
    }
    func refresh(_ credential: Credential) async throws -> Credential {
        let response = try await token(["grant_type": "refresh_token", "refresh_token": credential.refreshToken,
                                        "client_id": credential.client.clientID, "client_secret": credential.client.clientSecret])
        return Credential(client: credential.client, accessToken: response.access_token,
                          refreshToken: response.refresh_token ?? credential.refreshToken,
                          expiresAt: Date().addingTimeInterval(response.expires_in),
                          scopes: response.scope?.split(separator: " ").map(String.init) ?? credential.scopes)
    }
    func revoke(_ token: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"; request.httpBody = OAuth.form(["token": token])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw MeetError("Could not revoke access at Google. Try again online, or remove access in your Google Account.")
        }
    }
    func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request; request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MeetError("No response from Google.") }
        guard (200...299).contains(http.statusCode) else {
            // Do not display response bodies: these can contain credentials or user data.
            switch http.statusCode {
            case 400, 401: throw MeetError("Google login expired or was revoked. Open Calendar Meet and reconnect. (HTTP \(http.statusCode))")
            case 403: throw MeetError("Google denied access. Check Calendar API, consent, test users and your Workspace administrator. (HTTP 403)")
            case 404: throw MeetError("The Google Calendar event no longer exists.")
            case 412: throw MeetError("The event changed during setup. Waiting for Calendar to sync before retrying.")
            case 429: throw MeetError("Google's request limit was reached. Please try again later.")
            default: throw MeetError("Google could not complete the request (HTTP \(http.statusCode)). Try again later.")
            }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
import Security
