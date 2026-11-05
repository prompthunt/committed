import Foundation
import Security

/// The relay installation (ID, secret, registered flag) as one Keychain item, readable after
/// first unlock so a background launch can report a relay-started activity while the phone is
/// locked. Never backed up to another device: a restored phone registers as a new installation.
final class KeychainRelayInstallationStore: RelayInstallationStoring {
    private let service: String
    private let account = "installation"

    init(service: String = "com.addisonk.CommitStandings.iOS.relay") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> RelayInstallation? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(RelayInstallation.self, from: data)
    }

    func save(_ installation: RelayInstallation) {
        guard let data = try? JSONEncoder().encode(installation) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
