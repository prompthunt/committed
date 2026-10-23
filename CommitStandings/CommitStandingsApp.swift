import SwiftUI

@main
struct CommitStandingsApp: App {
    @State private var store: StandingsStore
    @State private var refresh: RefreshCoordinator
    @State private var auth: AuthModel
    @State private var roster: GitHubRoster
    @State private var notifications: NotificationService
    @State private var updater: AppUpdater

    init() {
        // Durable standings snapshot so relaunches show the last numbers immediately
        // and refresh in the background, instead of a cold, blank board every time.
        let isTesting = NSClassFromString("XCTestCase") != nil
        let store = isTesting
            ? StandingsStore(persistence: InMemoryCompetitorPersistence())
            : StandingsStore(snapshotPersistence: UserDefaultsStandingsSnapshotPersistence(),
                             hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence())
        // Credentials power sign-in + the automatic roster (GitHubAccountClient). The
        // contributions scrape is anonymous, so the standings client needs no token.
        // The test host must never prompt for or mutate the signed-in user's credentials.
        let credentials: any GitHubCredentialStoring = isTesting
            ? InMemoryGitHubCredentialStore() : KeychainGitHubCredentialStore()
        let roster = GitHubRoster(
            store: store, credentials: credentials,
            persistence: isTesting ? nil : UserDefaultsGitHubRosterPersistence(),
            legacyBackup: isTesting ? nil : UserDefaultsCompetitorPersistence(key: "competitors.manual-backup.v1")
        )
        _roster = State(initialValue: roster)
        let client = ContributionsClient()
        // Posts a local notification when a rival crosses you; refresh feeds it crossings.
        let notifications = NotificationService()
        let refresh = RefreshCoordinator(store: store, client: client, notifier: notifications, beforeRefresh: { reason in
            await roster.refresh(force: reason == .manual)
        })
        _store = State(initialValue: store)
        _refresh = State(initialValue: refresh)
        _notifications = State(initialValue: notifications)
        _auth = State(initialValue: AuthModel(
            credentials: credentials,
            auth: GitHubAuth(clientID: GitHubConfig.clientID, scope: GitHubConfig.scope),
            onSignedIn: { _ in await refresh.refreshAll(reason: .manual) },
            onSignedOut: { refresh.invalidate(); roster.disconnect() }
        ))
        _updater = State(initialValue: AppUpdater())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(updater: updater)
                .environment(store)
                .environment(refresh)
                .environment(auth)
                .environment(roster)
                .environment(notifications)
                .task {
                    if auth.isSignedIn {
                        // Re-fetch the display name each launch so the hero shows a real first
                        // name even on relaunch (sign-in didn't run this session).
                        await auth.refreshIdentity()
                        if refresh.shouldRefreshOnOpen {
                            await refresh.refreshAll(reason: .menuOpened)
                        }
                    }
                }
        } label: {
            MenuBarLabel()
                .environment(store)
                .environment(updater)
                .environment(auth)
                .environment(roster)
        }
        .menuBarExtraStyle(.window)

        // First-run onboarding lives in its own persistent window (the popover dismisses on
        // focus loss, which broke the GitHub browser hand-off). Singleton `Window`, so
        // re-opening focuses the existing one rather than spawning duplicates.
        Window("Set up Committed", id: OnboardingWindow.id) {
            OnboardingView()
                .environment(store)
                .environment(refresh)
                .environment(auth)
                .environment(roster)
        }
        .defaultSize(width: 520, height: 560)
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        // Explains the Contributions metric in a roomy, scannable window. Opened from the
        // dismissible board card and the ⋯ menu; singleton, so re-opening focuses it.
        Window("How contributions are counted", id: ExplainerWindow.id) {
            ContributionsExplainerView()
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        Window("People", id: FullRankingsWindow.id) {
            FullRankingsView()
                .environment(roster)
                .environment(store)
                .environment(refresh)
        }
        .defaultSize(width: 420, height: 480)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}

enum MenuPopoverLayout {
    static let width: CGFloat = 340
    static let maxHeight: CGFloat = 520
}

/// Preserve the existing singleton scene identity while opening the native manager.
enum FullRankingsWindow {
    static let id = "fullRankings"

    @MainActor
    static func open(_ openWindow: OpenWindowAction) {
        openAccessoryWindow(id: id, using: openWindow)
    }
}

/// Shared identity + open helper for the contributions-explainer window. Mirrors
/// `OnboardingWindow.open`: create the window first, then activate on the next runloop hop so
/// the new accessory-app window comes to the front focused (LSUIElement agent).
enum ExplainerWindow {
    static let id = "contributionsExplainer"

    @MainActor
    static func open(_ openWindow: OpenWindowAction) {
        openAccessoryWindow(id: id, using: openWindow)
    }
}

/// Open (or focus) a singleton accessory-app window and bring the app forward. Create the
/// window first, then activate on the next runloop hop: activating before the window exists
/// targets the stale window set and can leave the new accessory-app window unfocused/behind.
@MainActor
func openAccessoryWindow(id: String, using openWindow: OpenWindowAction) {
    openWindow(id: id)
    MacSystem.activateAfterOpeningWindow()
}

/// Shared identity + open helper for the onboarding window so the launch hook and the popover
/// launcher open the same singleton window and bring the app forward (LSUIElement agent).
enum OnboardingWindow {
    static let id = "onboarding"

    // Per-launch guard for the auto-open path. Static (not view @State) so it survives any
    // re-creation of the menu-bar label view that hosts the launch hook.
    @MainActor private static var didAutoOpen = false

    @MainActor
    static func open(_ openWindow: OpenWindowAction) {
        openAccessoryWindow(id: id, using: openWindow)
    }

    /// Auto-open exactly once per launch (signed-out first run). Manual re-entry goes through
    /// `open` directly so closing and reopening always works.
    @MainActor
    static func autoOpenOnce(_ openWindow: OpenWindowAction) {
        guard !didAutoOpen else { return }
        didAutoOpen = true
        open(openWindow)
    }
}
