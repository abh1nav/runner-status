import Foundation
import Security

enum Keychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "actions-runner-status",
        kSecAttrAccount as String: "github-token",
    ]

    static func readToken() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func writeToken(_ token: String) {
        SecItemDelete(base as CFDictionary)
        guard !token.isEmpty else { return }
        var query = base
        query[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }
}
