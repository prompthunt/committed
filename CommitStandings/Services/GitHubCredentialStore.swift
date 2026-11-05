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
    private let item: KeychainItem

    init(
        service: String = "com.addisonk.CommitStandings.github",
        account: String = "oauth-token"
    ) {
        item = KeychainItem(service: service, account: account)
    }

    func read() -> String? {
        item.read().flatMap { String(data: $0, encoding: .utf8) }
    }

    func save(_ token: String) {
        // Explicit least-privilege accessibility: readable only while unlocked, and
        // never migrated to another device via encrypted backups.
        item.save(Data(token.utf8), accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    func clear() {
        item.delete()
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
