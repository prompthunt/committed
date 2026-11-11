import SwiftUI

extension FinalStandings {
    /// "October final · You finished #2 of 6", over the rows.
    var statusLine: String? {
        result.map { "\($0.title) · \($0.body)" }
    }

    /// The leader's total, which shades every row's square.
    var maxContributions: Int {
        entries.compactMap(\.contributions).max() ?? 0
    }

    /// The board's shared row for `entry`, with its medal; a person without a calendar shows "—".
    @MainActor
    func row(_ entry: Entry) -> StandingRow {
        StandingRow(
            rank: entry.rank,
            competitor: entry.competitor,
            standing: entry.contributions.map { Self.standing(entry.competitor.username, total: $0) },
            window: .month,
            maxContributions: maxContributions,
            medal: entry.medal,
            period: month.name
        )
    }
}

/// "🏅 October final standings": switches the Board between the live board and last month's Final
/// standings, which it opens on each 1st. Mac and iPhone each style it.
struct FinalStandingsToggle: View {
    @Environment(RefreshCoordinator.self) private var refresh
    let finals: FinalStandings

    var body: some View {
        Toggle(isOn: Binding(
            get: { refresh.showsFinalStandings },
            set: { refresh.showFinalStandings($0) }
        )) {
            Text("🏅 \(finals.month.name) final standings")
                .frame(maxWidth: .infinity)
        }
        .toggleStyle(.button)
        .accessibilityHint("Shows how everyone finished \(finals.month.name)")
    }
}
