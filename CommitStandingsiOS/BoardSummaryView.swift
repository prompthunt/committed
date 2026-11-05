import SwiftUI

/// Your standing for the selected Window: avatar, name or handle, rank, Contributions,
/// today's movement, and how long ago Contributions refreshed. Text styles throughout so it
/// scales with Dynamic Type; at accessibility sizes it stacks vertically.
struct BoardSummaryView: View {
    let summary: Board.Summary
    @Environment(AuthModel.self) private var auth
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 52

    private var firstName: String? { DisplayName.firstName(from: auth.displayName) }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        VStack(alignment: .leading, spacing: 10) {
            layout {
                HStack(spacing: 12) {
                    AvatarView(username: summary.username, size: avatarSize)
                    identity
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                contributions
            }
            RefreshAge(lastUpdated: store.lastUpdated, isRefreshing: refresh.isRefreshing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.tint.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(firstName ?? "@\(summary.username)")
                .font(.headline)
                .lineLimit(1)
            if firstName != nil {
                Text("@\(summary.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // One line when it fits; at large text sizes the movement drops below the rank.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { rank; movement }
                VStack(alignment: .leading, spacing: 2) { rank; movement }
            }
        }
        .layoutPriority(1)
    }

    private var rank: some View {
        Text(rankText)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
    }

    @ViewBuilder
    private var movement: some View {
        if let movement = summary.movementToday {
            HStack(spacing: 4) {
                Image(systemName: movement > 0 ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(movement > 0 ? Color.green : Color.secondary)
                Text("\(movement.magnitude) today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }

    private var contributions: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
            Text(summary.contributions.map { $0.formatted() } ?? "—")
                .font(.largeTitle.weight(.semibold).width(.condensed).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .pulsing(summary.isRefreshing)
            Text("Contributions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rankText: String {
        guard let rank = summary.rank else {
            return summary.competitorCount > 1 ? "Rank —" : "Just you"
        }
        return "#\(rank) of \(summary.competitorCount)"
    }

    private var accessibilityLabel: String {
        var parts = ["You, @\(summary.username)"]
        if let rank = summary.rank {
            parts.append("rank \(rank) of \(summary.competitorCount)")
        }
        if let contributions = summary.contributions {
            parts.append("\(contributions) contributions for \(summary.window.accessibilityDescription)")
        } else {
            parts.append("no contributions data yet")
        }
        if let movement = summary.movementToday {
            let places = movement.magnitude == 1 ? "place" : "places"
            parts.append("\(movement > 0 ? "up" : "down") \(movement.magnitude) \(places) today")
        }
        if refresh.isRefreshing {
            parts.append("updating")
        } else if let lastUpdated = store.lastUpdated {
            parts.append("updated \(RelativeTimeFormatter.short(from: lastUpdated, to: Date()))")
        }
        return parts.joined(separator: ", ")
    }
}

/// "Updated 4m ago", or "Updating…" while a refresh runs. Ticks every 30 seconds.
private struct RefreshAge: View {
    let lastUpdated: Date?
    let isRefreshing: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                if isRefreshing {
                    Text("Updating…")
                } else if let lastUpdated {
                    Text("Updated \(RelativeTimeFormatter.short(from: lastUpdated, to: context.date))")
                } else {
                    Text("Not updated yet")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
