import XCTest
@testable import CommitStandings

final class UpdatePromptStateTests: XCTestCase {
    func testShowsWhenAvailableAndNotDismissed() {
        XCTAssertTrue(UpdatePromptState.shouldShowBanner(
            updateAvailable: true, latestVersion: "0.1.8", dismissedVersion: nil
        ))
    }

    func testHiddenWhenSameVersionDismissed() {
        XCTAssertFalse(UpdatePromptState.shouldShowBanner(
            updateAvailable: true, latestVersion: "0.1.8", dismissedVersion: "0.1.8"
        ))
    }

    func testShowsAgainForNewerVersionAfterDismissal() {
        // Dismissed 0.1.8, but 0.1.9 is a different string, so the banner returns.
        XCTAssertTrue(UpdatePromptState.shouldShowBanner(
            updateAvailable: true, latestVersion: "0.1.9", dismissedVersion: "0.1.8"
        ))
    }

    func testHiddenWhenNoUpdateAvailable() {
        XCTAssertFalse(UpdatePromptState.shouldShowBanner(
            updateAvailable: false, latestVersion: "0.1.8", dismissedVersion: nil
        ))
    }

    func testHiddenWhenVersionMissing() {
        XCTAssertFalse(UpdatePromptState.shouldShowBanner(
            updateAvailable: true, latestVersion: nil, dismissedVersion: nil
        ))
    }

    func testEmptyStoredStringTreatedAsNothingDismissed() {
        // @AppStorage defaults to "" — that must not equal a real version and must not suppress.
        XCTAssertTrue(UpdatePromptState.shouldShowBanner(
            updateAvailable: true, latestVersion: "0.1.8", dismissedVersion: ""
        ))
        XCTAssertNil(UpdatePromptState.normalized(""))
        XCTAssertEqual(UpdatePromptState.normalized("0.1.8"), "0.1.8")
    }

    func testEmptyLatestVersionDoesNotShow() {
        XCTAssertFalse(UpdatePromptState.shouldShowBanner(
            updateAvailable: true, latestVersion: "", dismissedVersion: nil
        ))
    }
}
