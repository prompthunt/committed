import SwiftUI

/// First-run flow hosted in a standalone, persistent window (not the menu-bar popover, which
/// dismisses on focus loss and would vanish during the GitHub browser hand-off). Renders the
/// sign-in view with room to breathe, and closes itself once
/// onboarding is complete. All state is derived from `AuthModel` via `OnboardingFlow`, so
/// closing and reopening the window resumes at the right step.
struct OnboardingView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private var step: OnboardingStep {
        OnboardingFlow.step(isSignedIn: auth.isSignedIn)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .signIn:
                SignInView()
            case .complete:
                // Transient — the onChange below closes the window as soon as we reach this.
                Color.clear
            }
        }
        .frame(width: 460)
        .frame(minHeight: 420)
        .padding(28)
        // Close on reaching .complete — onChange covers the in-session transition; onAppear
        // covers being opened (or state-restored) while already complete, which onChange misses.
        .onChange(of: step) { _, newStep in
            if newStep == .complete { dismiss() }
        }
        .onAppear {
            if step == .complete { dismiss() }
        }
    }
}
