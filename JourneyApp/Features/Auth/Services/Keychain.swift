import Foundation
import Security

// MARK: - Keychain
// A minimal wrapper around the Security framework's generic password store.
// Used only to persist authentication tokens; all other storage uses repositories.

enum Keychain {

    /// Stores a value for the given key, overwriting any existing entry.
    @discardableResult
    static func set(_ value: Data, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass    as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData   as String: value
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Retrieves the data stored for the given key, or nil if absent.
    static func get(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess ? (item as? Data) : nil
    }

    /// Removes the entry for the given key.
    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - AuthKeys
// Centralised constants for Keychain item identifiers.

enum AuthKeys {
    static let access  = "journey_access_token"
    static let refresh = "journey_refresh_token"
    static let userId  = "journey_user_id"
    static let email   = "journey_user_email"
}
