import XCTest
@testable import CommitStandings

final class OnboardingFlowTests: XCTestCase {
    func testSignedOutShowsSignInAndAutoOpens() {
        XCTAssertEqual(OnboardingFlow.step(isSignedIn: false), .signIn)
        XCTAssertTrue(OnboardingFlow.shouldAutoOpen(isSignedIn: false))
    }
    func testSignedInGoesDirectlyToAutomaticBoard() {
        XCTAssertEqual(OnboardingFlow.step(isSignedIn: true), .complete)
        XCTAssertFalse(OnboardingFlow.shouldAutoOpen(isSignedIn: true))
    }
}
