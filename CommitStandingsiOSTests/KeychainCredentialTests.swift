import Testing
import Foundation
@testable import CommitStandingsiOS

/// The production credential store on iPhone: the GitHub token lives in the Keychain.
@Suite(.serialized)
struct KeychainCredentialTests {

    @Test func theTokenRoundTripsThroughTheIPhoneKeychainAndClearsOnDisconnect() {
        // A test-only item, so the app's real token is never touched.
        let store = KeychainGitHubCredentialStore(service: "com.addisonk.CommitStandings.github.tests")
        store.clear()
        #expect(store.read() == nil)

        store.save("gho_first")
        store.save("gho_second")
        #expect(store.read() == "gho_second", "saving again replaces the token")

        store.clear()
        #expect(store.read() == nil)
    }
}
