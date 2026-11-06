import Security
import Testing
@testable import CommitStandings

struct GitHubCredentialStoreTests {

    @Test func saveReadClear_roundTrips() {
        let store = InMemoryGitHubCredentialStore()
        #expect(store.read() == nil)
        store.save("gho_abc")
        #expect(store.read() == "gho_abc")
        store.clear()
        #expect(store.read() == nil)
    }

    @Test func save_overwritesRatherThanDuplicates() {
        let store = InMemoryGitHubCredentialStore()
        store.save("gho_first")
        store.save("gho_second")
        #expect(store.read() == "gho_second")
    }

    @Test func seededToken_isReadable() {
        let store = InMemoryGitHubCredentialStore(token: "gho_seed")
        #expect(store.read() == "gho_seed")
    }

    /// The Mac keeps its token readable only while unlocked, as before the iPhone app. (The
    /// iPhone reads it after first unlock, so background refresh works while locked.)
    @Test func macKeepsTheTokenWhenUnlockedOnly() {
        #expect(KeychainGitHubCredentialStore.defaultAccessibility == kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        #expect(KeychainGitHubCredentialStore().service == "com.addisonk.CommitStandings.github")
    }

    /// One `read()` on both platforms: it moves a token the iPhone's pre-relay builds saved as
    /// "when unlocked" to the store's accessibility, and leaves everything else alone. The Mac
    /// wants "when unlocked" itself, so whatever its keychain reports, a Mac read never writes.
    @Test func readMigratesOnlyTheOldWhenUnlockedToken() {
        let whenUnlocked = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let afterFirstUnlock = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        // iPhone: the pre-relay token moves; one already after-first-unlock, or unreported, stays.
        #expect(KeychainGitHubCredentialStore.needsMigration(stored: whenUnlocked as String, to: afterFirstUnlock))
        #expect(!KeychainGitHubCredentialStore.needsMigration(stored: afterFirstUnlock as String, to: afterFirstUnlock))
        #expect(!KeychainGitHubCredentialStore.needsMigration(stored: nil, to: afterFirstUnlock))
        // Mac: never, whatever the file keychain reports.
        let mac = KeychainGitHubCredentialStore.defaultAccessibility
        for stored in [nil, whenUnlocked as String, kSecAttrAccessibleWhenUnlocked as String, afterFirstUnlock as String] {
            #expect(!KeychainGitHubCredentialStore.needsMigration(stored: stored, to: mac))
        }
    }
}
