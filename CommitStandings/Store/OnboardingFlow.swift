import Foundation

/// Which step the standalone onboarding window should show, derived purely from auth state.
/// Kept out of the view body (and AppKit-free) so the branching is unit-testable; the window
/// and popover both render from this.
enum OnboardingStep: Equatable {
    /// Not signed in yet — show the GitHub device-flow sign-in.
    case signIn
    /// Signed in — the roster loads automatically.
    case complete
}

enum OnboardingFlow {
    /// `connecting` (mid device-flow) is still `!isSignedIn`, so it maps to `.signIn` — the
    /// sign-in view renders the connecting phase itself.
    static func step(isSignedIn: Bool) -> OnboardingStep {
        guard isSignedIn else { return .signIn }
        return .complete
    }

    /// Auto-open the onboarding window at launch only for a signed-out user; a signed-in
    /// user goes straight to the popover board.
    static func shouldAutoOpen(isSignedIn: Bool) -> Bool {
        !isSignedIn
    }
}
