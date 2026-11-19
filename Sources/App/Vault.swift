import Foundation
import Security

enum Vault {
    // macOS login Keychain: only the containing app accesses credentials.
    // The extension never links this file or reads this Keychain item.
    static var isPreview: Bool { Bundle.main.object(forInfoDictionaryKey: "CMPreview") as? Bool ?? true }
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.mikkelrobin.CalendarMeet.local-oauth",
         kSecAttrAccount as String: "google"]
    }
    static func load() throws -> Credential? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return try JSONDecoder().decode(Credential.self, from: data)
    }
    static func save(_ credential: Credential) throws {
        let attributes = [kSecValueData as String: try JSONEncoder().encode(credential)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; attributes.forEach { q[$0.key] = $0.value }
            let added = SecItemAdd(q as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    static func failure(_ status: OSStatus) -> MeetError {
        MeetError("Login Keychain unavailable (\(status)). Unlock your login Keychain, then try again.")
    }
}

actor ConferenceService {
    static let shared = ConferenceService()
    func create() async throws -> URL {
        guard var credential = try Vault.load(), credential.supportsMeet else {
            throw MeetError("Reconnect Google Account to allow creating Meet links.")
        }
        let api = GoogleAPI()
        if credential.expiresAt < Date().addingTimeInterval(60) {
            credential = try await api.refresh(credential)
            try Task.checkCancellation()
            try Vault.save(credential)
        }
        try Task.checkCancellation()
        // Never retry a POST automatically: a lost response can already have created a space.
        return try await api.createSpace(accessToken: credential.accessToken)
    }
}
