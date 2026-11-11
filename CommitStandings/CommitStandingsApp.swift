import SwiftUI

@main
struct CommitStandingsApp: App {
    @State private var store: StandingsStore
    @State private var refresh: RefreshCoordinator
    @State private var auth: AuthModel
    @State private var roster: GitHubRoster
    @State private var notifications: NotificationService
    @State private var updater: AppUpdater
    @State private var personWindow: PersonWindowModel

    init() {
        // One shared graph for Mac and iPhone (see CommittedServices): durable snapshot so
        // relaunches show the last numbers immediately, Keychain token, automatic roster. The
        // test host gets in-memory storage and never touches the signed-in user's credentials.
        let services = CommittedServices.live()
        _store = State(initialValue: services.store)
        _roster = State(initialValue: services.roster)
        _refresh = State(initialValue: services.refresh)
        _notifications = State(initialValue: services.notifications)
        _auth = State(initialValue: services.auth)
        _updater = State(initialValue: AppUpdater())
        _personWindow = State(initialValue: PersonWindowModel(store: services.store))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(updater: updater)
                .environment(store)
                .environment(refresh)
                .environment(auth)
                .environment(roster)
                .environment(notifications)
                .environment(personWindow)
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

        // One person at a time, opened by clicking a board row: clicking someone else switches it
        // to them, and clicking the person shown brings it forward. Not restored at launch, when
        // nobody has been clicked yet.
        Window("Person", id: PersonWindow.id) {
            PersonWindowView()
                .environment(personWindow)
        }
        .defaultSize(width: PersonWindow.defaultWidth, height: 640)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .restorationBehavior(.disabled)
    }
}

enum MenuPopoverLayout {
    static let width: CGFloat = 340
    static let maxHeight: CGFloat = 520
}

/// The person window's identity and opener. Shows `login` in the one person window, then opens it,
/// or brings it forward when it's already open (LSUIElement agent, so activate after opening).
enum PersonWindow {
    static let id = "person"
    static let defaultWidth: CGFloat = 460
    static let minWidth: CGFloat = 400

    @MainActor
    static func open(_ login: String, model: PersonWindowModel, using openWindow: OpenWindowAction) {
        model.show(login)
        openAccessoryWindow(id: id, using: openWindow)
    }
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
