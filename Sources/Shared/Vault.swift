import Foundation
import Security

enum Vault {
    static let group = "group.com.mikkelrobin.CalendarMeet"
    static var isPreview: Bool { Bundle.main.object(forInfoDictionaryKey: "CMPreview") as? Bool ?? true }
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.mikkelrobin.CalendarMeet.oauth",
         kSecAttrAccount as String: "google", kSecAttrAccessGroup as String: group,
         kSecUseDataProtectionKeychain as String: true]
    }
    static func requireSigned() throws {
        guard !isPreview else { throw MeetError("This is an unsigned developer preview. A signed build with App Group provisioning is required for secure Google login shared with Calendar. See Setup in the source package.") }
    }
    static func load() throws -> Credential? {
        try requireSigned()
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return try JSONDecoder().decode(Credential.self, from: data)
    }
    static func save(_ credential: Credential) throws {
        try requireSigned()
        let attributes = [kSecValueData as String: try JSONEncoder().encode(credential)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; attributes.forEach { q[$0.key] = $0.value }
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    static func remove() throws {
        try requireSigned()
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    static func failure(_ status: OSStatus) -> MeetError {
        MeetError("Shared Keychain unavailable (\(status)). Check both provisioning profiles, App Group entitlements and signing team; unlock your Mac, then reconnect.")
    }
}

actor ConferenceService {
    static let shared = ConferenceService()
    // Serialize refresh and space requests within each process. Refresh tokens are preserved.
    private var tail: Task<Void, Never>?
    func create() async throws -> URL {
        let previous = tail
        let work = Task<URL, Error> {
            await previous?.value
            guard var credential = try Vault.load() else { throw MeetError("Open Calendar Meet and connect Google first.") }
            let api = GoogleAPI()
            if credential.expiresAt < Date().addingTimeInterval(60) {
                credential = try await api.refresh(credential)
                try Vault.save(credential)
            }
            // Never automatically retry a POST: a lost response may already have created a space.
            return try await api.createSpace(accessToken: credential.accessToken)
        }
        tail = Task { _ = try? await work.value }
        return try await work.value
    }
}
