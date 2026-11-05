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
    let service: String
    private let account: String
    private let accessibility: CFString

    /// The Mac keeps the token readable only while unlocked. The iPhone needs it after first
    /// unlock: background refresh and a background launch run while the phone is locked, and a
    /// token that reads as nil there would look like a Disconnect.
    static var defaultAccessibility: CFString {
        #if os(iOS)
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #else
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
    }

    init(
        service: String = "com.addisonk.CommitStandings.github",
        account: String = "oauth-token",
        accessibility: CFString = KeychainGitHubCredentialStore.defaultAccessibility
    ) {
        self.service = service
        self.account = account
        self.accessibility = accessibility
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
        query[kSecReturnAttributes as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any],
              let data = attributes[kSecValueData as String] as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        // iPhone builds before the Committed relay (#45) saved it as "when unlocked": move it over.
        if Self.needsMigration(stored: attributes[kSecAttrAccessible as String] as? String, to: accessibility) {
            SecItemUpdate(baseQuery as CFDictionary, [kSecAttrAccessible as String: accessibility] as CFDictionary)
        }
        return token
    }

    /// Whether a token saved with `stored` accessibility should move to `wanted`. Only the old
    /// "when unlocked" token moves, and only to something else: the iPhone's pre-relay builds saved
    /// it that way. The Mac wants "when unlocked" itself, so a Mac read never writes, whatever its
    /// file keychain reports.
    static func needsMigration(stored: String?, to wanted: CFString) -> Bool {
        let whenUnlocked = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        return stored == whenUnlocked && wanted as String != whenUnlocked
    }

    func save(_ token: String) {
        // Delete-then-add keeps the item unique (an update would otherwise duplicate).
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(token.utf8)
        // Explicit least-privilege accessibility (see `defaultAccessibility`), never migrated to
        // another device via encrypted backups.
        attributes[kSecAttrAccessible as String] = accessibility
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
