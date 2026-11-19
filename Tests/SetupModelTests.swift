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
    func token() async throws -> String {
        inFlight = true
        defer { inFlight = false }
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return "never-returned-test-token"
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
        let pending = PendingConference.make()
        preferences.set(try JSONEncoder().encode([pending]), forKey: "pendingCalendarConferences")
        preferences.set([pending.id: "https://meet.google.com/abc-defg-hij"], forKey: "resolvedCalendarConferences")
        let model = SetupModel()
        expect(model.connected, "Existing Calendar login starts connected (green status)")
        model.startReconciliation()
        for _ in 0..<1000 { if await ConferenceService.shared.inFlight { break }; await Task.yield() }
        expect(await ConferenceService.shared.inFlight, "Test simulates an in-flight refresh")
        model.signOut()
        model.signOut()
        expect(model.busy, "Sign-out is busy until in-flight work stops")
        for _ in 0..<1000 { if !model.busy { break }; await Task.yield() }
        expect(!model.busy, "Sign-out finishes without waiting for refresh deadline")
        expect(!(await ConferenceService.shared.inFlight), "In-flight refresh was cancelled before deleting login")
        expect(Vault.removeCount == 1, "Repeated clicks cannot remove twice")
        expect(Vault.credential == nil, "Sign-out removes local credentials")
        expect(!model.connected, "Sign-out publishes disconnected (red status)")
        expect(model.client == client, "Retain team configuration for signing in again")
        let saved = try JSONDecoder().decode([PendingConference].self, from: preferences.data(forKey: "pendingCalendarConferences")!)
        expect(saved.isEmpty, "Queued work cannot follow the next Google account")
        expect(preferences.dictionary(forKey: "resolvedCalendarConferences") == nil, "Clear account-specific resolved links")
        Vault.credential = credential; Vault.failRemoval = true
        let failure = SetupModel()
        failure.signOut()
        for _ in 0..<1000 { if !failure.busy { break }; await Task.yield() }
        expect(failure.connected && Vault.credential != nil, "Failed removal does not falsely report signed out")
        expect(!failure.message.isEmpty, "Report credential deletion errors")
        print("Passed \(checks) isolated model checks: sign-out, cancellation, credential removal, account isolation and connection status.")
    }
}
