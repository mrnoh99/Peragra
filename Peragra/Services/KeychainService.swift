import Foundation
import Security

/// Minimal Keychain wrapper for storing the user's own API keys on-device
/// (the AI extraction gateway, Google Maps, ...). This app has no server —
/// every feature that needs one of these calls that provider's API
/// directly from the device using the key, which never leaves it except
/// in that request.
enum KeychainService {
    private static let service = "com.peragra.app.keychain"

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func save(_ value: String, for key: String) {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(for key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }
}
