import Foundation
import Security
import Testing
@testable import CommitStandingsiOS

/// On iPhone, background refresh and relay reporting run while the phone is locked, so the GitHub
/// token and the relay's install secret must be readable after first unlock. Uses its own
/// Keychain service names, never the app's real items.
@Suite(.serialized)
struct KeychainAccessibilityTests {
    private let service = "com.addisonk.CommitStandings.tests.\(UUID().uuidString)"

    private func accessibility(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any] else { return nil }
        return attributes[kSecAttrAccessible as String] as? String
    }

    private func delete(service: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    @Test func iPhoneSavesTheTokenForAfterFirstUnlock() {
        defer { delete(service: service) }
        let store = KeychainGitHubCredentialStore(service: service)

        store.save("gho_new")

        #expect(store.read() == "gho_new")
        #expect(accessibility(service: service, account: "oauth-token")
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test func aTokenSavedByAnEarlierBuildMovesToAfterFirstUnlockOnRead() {
        defer { delete(service: service) }
        // What builds before #45 saved: readable only while unlocked.
        SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "oauth-token",
            kSecValueData as String: Data("gho_old".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ] as CFDictionary, nil)

        let token = KeychainGitHubCredentialStore(service: service).read()

        #expect(token == "gho_old")
        #expect(accessibility(service: service, account: "oauth-token")
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test func relayInstallationRoundTripsAfterFirstUnlock() {
        defer { delete(service: service) }
        let store = KeychainRelayInstallationStore(service: service)
        #expect(store.load() == nil)

        let installation = RelayInstallation(id: "install-1234", secret: String(repeating: "a", count: 64), isRegistered: true)
        store.save(installation)
        store.save(installation)

        #expect(store.load() == installation)
        #expect(accessibility(service: service, account: "installation")
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }
}
