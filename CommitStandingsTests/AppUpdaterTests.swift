import XCTest
@testable import CommitStandings

@MainActor
final class AppUpdaterTests: XCTestCase {
    /// `startingUpdater: false` keeps Sparkle's scheduler from starting under test — we only
    /// exercise the observable lifecycle state, not the real update session.
    private func makeUpdater() -> AppUpdater {
        AppUpdater(startingUpdater: false)
    }

    func testAutomaticUpdatePreferenceUsesSparkleAndPersists() throws {
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        let keys = ["SUAutomaticallyUpdate", "SUEnableAutomaticChecks"]
        defer {
            for key in keys {
                if let value = original[key] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }

        let updater = makeUpdater()
        updater.setAutomaticUpdates(true)
        XCTAssertTrue(updater.automaticallyDownloadsUpdates)
        XCTAssertTrue(defaults.bool(forKey: "SUAutomaticallyUpdate"))
        XCTAssertTrue(defaults.bool(forKey: "SUEnableAutomaticChecks"))

        updater.setAutomaticUpdates(false)
        XCTAssertFalse(updater.automaticallyDownloadsUpdates)
        XCTAssertFalse(makeUpdater().automaticallyDownloadsUpdates)
        // A user's opt-out survives relaunch and doesn't disable update checks.
        XCTAssertTrue(defaults.bool(forKey: "SUEnableAutomaticChecks"))
    }

    func testStartsWithNoUpdateAvailable() {
        let updater = makeUpdater()
        XCTAssertFalse(updater.updateAvailable)
        XCTAssertNil(updater.latestVersion)
    }

    func testMarkUpdateFoundSetsAvailabilityAndVersion() {
        let updater = makeUpdater()
        updater.markUpdateFound("0.1.8")
        XCTAssertTrue(updater.updateAvailable)
        XCTAssertEqual(updater.latestVersion, "0.1.8")
    }

    func testMarkUpdateResolvedClearsBothAvailabilityAndVersion() {
        // Regression: latestVersion must not linger after the indicator is cleared — the two
        // always move together so a later markUpdateFound can't briefly read a phantom version.
        let updater = makeUpdater()
        updater.markUpdateFound("0.1.8")
        updater.markUpdateResolved()
        XCTAssertFalse(updater.updateAvailable)
        XCTAssertNil(updater.latestVersion)
    }
}
