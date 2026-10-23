import Foundation
import Security

/// Stores the GitHub access token. The token never leaves storage except to be
/// attached to a request `Authorization` header.
protocol GitHubCredentialStoring: Sendable {
    func read() -> String?
    func save(_ token: String)
    func clear()
}

/// Keychain-backed store (generic password keyed by service + account). Works under
/// the app sandbox with no extra entitlement for the app's own keychain item.
final class KeychainGitHubCredentialStore: GitHubCredentialStoring, @unchecked Sendable {
    private let service: String
    private let account: String

    init(
        service: String = "com.addisonk.CommitStandings.github",
        account: String = "oauth-token"
    ) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Never block app launch on an interactive keychain prompt: if the item can't be read
        // without UI (e.g. an ACL/signature mismatch, as happens with ad-hoc dev/test builds),
        // fail gracefully to nil (signed-out) rather than hanging the main thread on a dialog.
        // The Developer ID-signed release reads its own item without any UI, so this is a no-op
        // there.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    func save(_ token: String) {
        // Delete-then-add keeps the item unique (an update would otherwise duplicate).
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(token.utf8)
        // Explicit least-privilege accessibility: readable only while unlocked, and
        // never migrated to another device via encrypted backups.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// In-memory double for tests (no real Keychain dependency in CI).
final class InMemoryGitHubCredentialStore: GitHubCredentialStoring, @unchecked Sendable {
    private var token: String?
    init(token: String? = nil) { self.token = token }
    func read() -> String? { token }
    func save(_ token: String) { self.token = token }
    func clear() { token = nil }
}
