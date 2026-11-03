import Foundation
import Security

/// The SignUpGenius API key, kept in the login keychain rather than in a
/// preferences file or next to the event data.
///
/// The item lives in the file-based login keychain and is protected by its
/// access list. The data protection keychain is not used because it needs a
/// provisioning profile, and `kSecAttrAccessible` only applies there.
enum SignUpGeniusKeychain {
    private static let service = "Eagle Boards SignUpGenius API key"
    private static let account = "default"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Whether a key is stored, without reading it. Asking only for the
    /// item's attributes does not unlock the secret, so it never prompts.
    static func exists() -> Bool {
        var lookup = query
        lookup[kSecReturnAttributes as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(lookup as CFDictionary, nil) == errSecSuccess
    }

    /// Reads the stored key. Unlike `exists()`, this asks for the secret, so
    /// macOS may show a keychain access prompt.
    ///
    /// - Returns: The key, or nil when none is stored or it is empty.
    static func read() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    /// Store `key`, or remove the stored one when `key` is empty. A key
    /// already stored is updated in place, so a refused write (a locked
    /// keychain, a denied prompt) leaves the working key where it was.
    /// - Returns: Whether the keychain now holds what was asked for.
    @discardableResult
    static func write(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(trimmed.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        var item = query
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
