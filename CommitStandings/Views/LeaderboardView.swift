import SwiftUI

struct LeaderboardView: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(\.openWindow) private var openWindow

    /// The first cold load before any row has data: show one explainer instead of a
    /// spinner in every cell. Once any standing has loaded, this turns off for good.
    private var isInitialLoad: Bool {
        guard refresh.isRefreshing else { return false }
        return !store.visibleCompetitors.contains { person in
            guard let standing = store.standing(for: person.username, window: store.selectedWindow) else { return false }
            return standing.lastUpdated != .distantPast
        }
    }

    var body: some View {
        // Every visible competitor belongs in the main list. MenuContentView caps
        // the viewport and scrolls; ranking must never decide who is tracked.
        let window = store.selectedWindow
        let standings = store.standings(for: window)
        let entries = Ranking.order(
            competitors: store.visibleCompetitors, standings: standings, window: window
        )
        let maxContributions = store.visibleCompetitors.compactMap { standings[$0.username] }
            .filter { $0.lastUpdated != .distantPast }
            .map(\.contributions).max() ?? 0
        VStack(alignment: .leading, spacing: 0) {
            if isInitialLoad {
                InitialLoadingBanner()
                    .padding(.bottom, 6)
            }
            HStack {
                Text("Tracking \(entries.count) people")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("People…") {
                    FullRankingsWindow.open(openWindow)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("View GitHub sources for \(entries.count) people")
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            LazyVStack(spacing: 0) {
                ForEach(entries) { item in
                    row(for: item, maxContributions: maxContributions)
                }
            }
        }
    }

    private func row(for item: Ranking.Entry, maxContributions: Int) -> some View {
        StandingRow(
            rank: item.rank,
            competitor: item.competitor,
            standing: store.standing(for: item.competitor.username, window: store.selectedWindow),
            window: store.selectedWindow,
            maxContributions: maxContributions,
            rankDelta: rankDelta(for: item.competitor.username)
        )
    }

    /// Placement movement since the start of the day — only meaningful (and only shown) on the
    /// Today board; the 7/30-day positions barely move hour to hour.
    private func rankDelta(for username: String) -> Int? {
        guard store.selectedWindow == .daily else { return nil }
        return refresh.rankDelta(for: username)
    }

    /// Shown once, on the very first sync, in place of a board full of spinners.
    private struct InitialLoadingBanner: View {
        var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(.tint)
                    .frame(width: 7, height: 7)
                    .pulsing(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Fetching the first set of standings")
                        .font(.caption.weight(.medium))
                    Text("This only happens once — just a moment.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.5)))
        }
    }
}
