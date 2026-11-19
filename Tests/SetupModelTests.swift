import Foundation

// Isolated credential store: these tests never access the user's Keychain.
enum Vault {
    static var credential: Credential?
    static var removeCount = 0
    static var failRemoval = false
    static func load() throws -> Credential? { credential }
    static func save(_ value: Credential) throws { credential = value }
    static func remove() throws {
        removeCount += 1
        if failRemoval { throw MeetError("Test credential removal failed") }
        credential = nil
    }
}
actor ConferenceService {
    static let shared = ConferenceService()
    var inFlight = false
    func create() async throws -> URL {
        inFlight = true
        defer { inFlight = false }
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return URL(string: "https://meet.google.com/abc-defg-hij")!
    }
}
@main struct SetupModelTests {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ value: Bool, _ label: String) { precondition(value, label); checks += 1 }
        let preferences = UserDefaults.standard
        defer {
            preferences.removeObject(forKey: "pendingCalendarConferences")
            preferences.removeObject(forKey: "resolvedCalendarConferences")
        }
        let client = OAuthClient(clientID: "test.apps.googleusercontent.com", clientSecret: "public-desktop-test")
        let credential = Credential(client: client, accessToken: "test", refreshToken: "test", expiresAt: .distantFuture, scopes: OAuth.scopes)
        Vault.credential = credential
        let pendingID = "test-retired-request"
        preferences.set(Data("[]".utf8), forKey: "pendingCalendarConferences")
        preferences.set([pendingID: "https://meet.google.com/abc-defg-hij"], forKey: "resolvedCalendarConferences")
        let model = SetupModel()
        expect(model.connected, "Existing Calendar login starts connected (green status)")
        let listener = try BridgeListener()
        let callback = try await listener.start(timeout: 10)
        defer { listener.cancel() }
        model.handleBridge(BridgeRequest.url(callback: callback))
        for _ in 0..<500 { if await ConferenceService.shared.inFlight { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        expect(await ConferenceService.shared.inFlight, "Test simulates an in-flight refresh")
        model.signOut()
        model.signOut()
        expect(model.busy, "Sign-out is busy until in-flight work stops")
        for _ in 0..<500 { if !model.busy { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        expect(!model.busy, "Sign-out finishes without waiting for refresh deadline")
        expect(!(await ConferenceService.shared.inFlight), "In-flight refresh was cancelled before deleting login")
        expect(Vault.removeCount == 1, "Repeated clicks cannot remove twice")
        expect(Vault.credential == nil, "Sign-out removes local credentials")
        expect(!model.connected, "Sign-out publishes disconnected (red status)")
        expect(model.client == client, "Retain team configuration for signing in again")
        expect(preferences.data(forKey: "pendingCalendarConferences") == nil, "Retired Calendar-patching jobs are not replayed")
        expect(preferences.dictionary(forKey: "resolvedCalendarConferences") == nil, "Clear account-specific resolved links")
        Vault.credential = credential; Vault.failRemoval = true
        let failure = SetupModel()
        failure.signOut()
        for _ in 0..<500 { if !failure.busy { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        expect(failure.connected && Vault.credential != nil, "Failed removal does not falsely report signed out")
        expect(!failure.message.isEmpty, "Report credential deletion errors")
        print("Passed \(checks) isolated model checks: sign-out, cancellation, credential removal, account isolation and connection status.")
    }
}
