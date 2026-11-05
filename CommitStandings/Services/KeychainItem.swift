import Foundation
import Security

/// One generic-password Keychain item, keyed by service and account. Shared by the GitHub token
/// store (Mac and iPhone) and the iPhone's relay identity. Each caller keeps its own service,
/// account, and accessibility, so existing items stay readable across updates.
struct KeychainItem: Sendable {
    let service: String
    let account: String

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// The item's data, or nil when there's none or it can't be read.
    func read() -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Never block on an interactive keychain prompt: if the item can't be read without UI
        // (e.g. an ACL/signature mismatch, as happens with ad-hoc dev/test builds), fail
        // gracefully to nil rather than hanging the main thread on a dialog. A correctly signed
        // build reads its own item without any UI, so this is a no-op there.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    /// Replace the item. Delete-then-add keeps it unique (an update would otherwise duplicate).
    func save(_ data: Data, accessibility: CFString) {
        delete()
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = accessibility
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
