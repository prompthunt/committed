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
}
