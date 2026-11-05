import SwiftUI

/// You first: avatar, name or handle, rank, Contributions for the Window, today's movement, how
/// long ago the numbers refreshed, and people-sync status. Text styles throughout so it grows with
/// Dynamic Type; at accessibility sizes the numbers move below your name.
struct BoardSummaryView: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(AuthModel.self) private var auth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 52

    private var summary: BoardSummary? {
        BoardSummary.make(
            competitors: store.visibleCompetitors,
            standings: store.standings(for: store.selectedWindow),
            window: store.selectedWindow,
            displayName: auth.displayName,
            rankDelta: { refresh.rankDelta(for: $0) },
            lastUpdated: store.lastUpdated
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary {
                card(summary)
            }
            RosterStatusView()
        }
    }

    private func card(_ summary: BoardSummary) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        let isRefreshingMine = store.standing(for: summary.username, window: summary.window)?.state == .loading
            && summary.contributions != nil

        return VStack(alignment: .leading, spacing: 10) {
            layout {
                HStack(spacing: 12) {
                    AvatarView(username: summary.username, size: avatarSize)
                    VStack(alignment: .leading, spacing: 1) {
                        if let firstName = summary.firstName {
                            Text(firstName).font(.headline)
                            Text("@\(summary.username)").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("@\(summary.username)").font(.headline)
                        }
                    }
                    .lineLimit(stacked ? 2 : 1)
                    .truncationMode(.middle)
                }
                if !stacked { Spacer(minLength: 8) }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    if let rank = summary.rank {
                        metric(value: "#\(rank)", caption: "of \(summary.competitorCount)")
                    }
                    metric(value: summary.contributions?.formatted() ?? "—", caption: "contributions")
                        .pulsing(isRefreshingMine)
                }
            }
            footer(summary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.tint.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityDescription)
        .accessibilityValue(refreshAgeText(summary.lastUpdated, now: .now) ?? "")
    }

    private func metric(value: String, caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(.title.weight(.semibold).width(.condensed))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2.weight(.medium))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func footer(_ summary: BoardSummary) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 10) {
                if let movement = summary.movementToday {
                    Label(movement > 0 ? "Up \(movement) today" : "Down \(-movement) today",
                          systemImage: movement > 0 ? "chevron.up" : "chevron.down")
                        .foregroundStyle(movement > 0 ? Color.green : Color.secondary)
                }
                if let age = refreshAgeText(summary.lastUpdated, now: context.date) {
                    Text(age)
                } else if refresh.isRefreshing {
                    Text("Updating…")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func refreshAgeText(_ lastUpdated: Date?, now: Date) -> String? {
        guard let lastUpdated else { return nil }
        let age = RelativeTimeFormatter.short(from: lastUpdated, to: now)
        return age == "just now" ? "Updated just now" : "Updated \(age)"
    }
}
