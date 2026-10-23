import SwiftUI

struct MenuBarLabel: View {
    @Environment(StandingsStore.self) private var store
    @Environment(AppUpdater.self) private var updater
    @Environment(AuthModel.self) private var auth
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
                .accessibilityHidden(true)
                // Soft "update waiting" signal — a small dot rides the icon. The menu bar may
                // render this monochrome (template), which is fine: a dot is still a signal.
                .overlay(alignment: .topTrailing) {
                    if updater.updateAvailable {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .offset(x: 2, y: -1)
                    }
                }
            if let rank = currentRank {
                Text("#\(rank)")
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .task {
            // Present onboarding once on a signed-out launch so a fresh install gets the clear
            // window without having to discover the menu bar first.
            guard OnboardingFlow.shouldAutoOpen(isSignedIn: auth.isSignedIn) else { return }
            OnboardingWindow.autoOpenOnce(openWindow)
        }

    }

    var accessibilityDescription: String {
        let base: String
        if let rank = currentRank {
            base = "Committed — rank \(rank)"
        } else {
            base = "Committed"
        }
        return updater.updateAvailable ? "\(base) — update available" : base
    }

    var currentRank: Int? {
        guard let me = store.selfCompetitor else { return nil }
        // Solo: no rank to show.
        guard !store.rivals.isEmpty else { return nil }
        let ranked = Ranking.order(
            competitors: store.visibleCompetitors,
            standings: store.standings(for: store.selectedWindow),
            window: store.selectedWindow
        )
        return ranked.first(where: { $0.competitor.id == me.id })?.rank
    }
}
