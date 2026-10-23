import Foundation
import AppKit
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater {
    /// True while Sparkle has a scheduled (non-user-initiated) update waiting that we chose to
    /// surface ourselves instead of letting the standard driver pop an unfocused alert.
    private(set) var updateAvailable = false
    /// Display version of the waiting update (e.g. "0.1.8"), for the banner and menu labels.
    private(set) var latestVersion: String?

    private(set) var automaticallyDownloadsUpdates = false
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var settingObservers: [NSKeyValueObservation] = []
    @ObservationIgnored private let updaterController: SPUStandardUpdaterController
    // Retained because SPUStandardUpdaterController holds the user-driver delegate weakly.
    @ObservationIgnored private let driverDelegate = GentleReminderDelegate()

    init(startingUpdater: Bool = !AppUpdater.isRunningTests) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: driverDelegate
        )
        driverDelegate.updater = self
        // Sparkle owns these preferences. Bridge its KVO changes into Observation
        // so both our checkbox and manual-check button stay in sync with its UI.
        settingObservers = [
            updaterController.updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated {
                    self?.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
                }
            },
            updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated {
                    self?.canCheckForUpdates = updater.canCheckForUpdates
                }
            }
        ]
    }

    // internal (not private) so the found→resolved lifecycle can be regression-tested.
    func markUpdateFound(_ version: String?) {
        updateAvailable = true
        latestVersion = version
    }

    func markUpdateResolved() {
        // Clear both together so latestVersion never lingers as a phantom once the indicator
        // is gone — every reader gates on updateAvailable, but keeping them in sync is safer.
        updateAvailable = false
        latestVersion = nil
    }

    /// Change Sparkle's own preferences only in response to an explicit user action.
    /// Enabling downloads also enables scheduled checks; disabling keeps checks available.
    func setAutomaticUpdates(_ enabled: Bool) {
        if enabled { updaterController.updater.automaticallyChecksForUpdates = true }
        updaterController.updater.automaticallyDownloadsUpdates = enabled
    }

    /// Manual "Check for Updates…": activate first so the dialog is visible (this is an
    /// LSUIElement agent), then run a user-initiated check.
    func checkForUpdates() {
        activateAndShowUpdates()
    }

    /// User tapped the in-app "Update" affordance for a gently-surfaced update. Same call as
    /// the manual check: when a scheduled update is already in progress, Sparkle short-circuits
    /// checkForUpdates to bring that pending alert into focus rather than re-fetching.
    func installUpdate() {
        activateAndShowUpdates()
    }

    private func activateAndShowUpdates() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}

/// Implements Sparkle's "gentle reminders" so a scheduled update is surfaced via our own
/// menu-bar dot + popover banner instead of a focus-stealing alert. NSObject-based because
/// SPUStandardUserDriverDelegate is an Objective-C protocol. Sparkle's standard user driver
/// invokes these on the main thread, so we use `MainActor.assumeIsolated` to touch the
/// @MainActor @Observable AppUpdater state without sending the delegate across an actor.
private final class GentleReminderDelegate: NSObject, SPUStandardUserDriverDelegate {
    // AppUpdater is @MainActor-isolated (hence Sendable), so capturing this weak reference into
    // the main-actor hops below is safe — we never send the non-Sendable delegate itself.
    weak var updater: AppUpdater?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    // Tell the standard driver not to show scheduled updates itself; we present our own
    // indicators instead. (Never called for user-initiated checks — those still show normally.)
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // We only own the scheduled case we declined above (handleShowingUpdate == false).
        // User-initiated checks are handled by the standard driver and need no banner.
        guard !handleShowingUpdate, !state.userInitiated else { return }
        let version = update.displayVersionString
        let updater = updater
        MainActor.assumeIsolated { updater?.markUpdateFound(version) }
    }

    // Deliberately NOT implementing standardUserDriverDidReceiveUserAttentionForUpdate: it fires
    // the instant Sparkle's alert gains focus — before the user chooses Install vs Later — so
    // clearing there would drop the dot/banner the moment the user clicks "Update" to look,
    // and never bring it back if they defer (until the next scheduled check). We clear only on
    // the true terminal below, keeping the gentle reminder alive through the decision window.
    func standardUserDriverWillFinishUpdateSession() {
        let updater = updater
        MainActor.assumeIsolated { updater?.markUpdateResolved() }
    }
}
