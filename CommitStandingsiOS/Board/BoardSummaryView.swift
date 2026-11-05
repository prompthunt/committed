import SwiftUI

/// You first, as the site's hero: your rank set huge over a lit field of contribution squares,
/// your Contributions for the Window in lime, today's movement, how long ago the numbers
/// refreshed, and people-sync status. When your rank improves, squares burst out of it.
///
/// Every size follows Dynamic Type; at accessibility sizes the numbers stack under your name.
/// VoiceOver reads the card as one sentence (`BoardSummary.accessibilityDescription`).
struct BoardSummaryView: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(AuthModel.self) private var auth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var trophySize: CGFloat = 58
    /// Bumped each time your rank improves, to fire `RankBurst`.
    @State private var bursts = 0

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
        let summary = summary
        VStack(alignment: .leading, spacing: 10) {
            if let summary {
                card(summary)
            }
            RosterStatusView()
                .padding(.horizontal, 6)
        }
        .onChange(of: BurstKey(rank: summary?.rank, window: store.selectedWindow)) { old, new in
            // Only a real climb within one Window: switching Windows can also lower the number.
            if old.window == new.window, let before = old.rank, let after = new.rank, after < before {
                bursts += 1
            }
        }
    }

    private func card(_ summary: BoardSummary) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let isRefreshingMine = store.standing(for: summary.username, window: summary.window)?.state == .loading
            && summary.contributions != nil

        return VStack(alignment: .leading, spacing: 18) {
            identity(summary, stacked: stacked)
            numbers(summary, stacked: stacked, pulsing: isRefreshingMine)
            footer(summary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            AnimatedSquareField(light: UnitPoint(x: 0.88, y: 0.05), reach: 0.7, cell: 15, brightness: 0.8, maxLevel: 3)
                // Keep the field behind the numbers, not under your name.
                .mask(LinearGradient(colors: [.clear, .black.opacity(0.55), .black], startPoint: .leading, endPoint: .trailing))
        }
        .tileCard(cornerRadius: 22)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityDescription)
        .accessibilityValue(refreshAgeText(summary.lastUpdated, now: .now) ?? "")
    }

    private func identity(_ summary: BoardSummary, stacked: Bool) -> some View {
        HStack(spacing: 10) {
            AvatarView(username: summary.username, size: avatarSize)
                .overlay { Circle().strokeBorder(Color.lime.opacity(0.6), lineWidth: 1.5) }
            VStack(alignment: .leading, spacing: 0) {
                if let firstName = summary.firstName {
                    Text(firstName).font(.headline)
                    Text("@\(summary.username)").font(.subheadline).foregroundStyle(Color.muted)
                } else {
                    Text("@\(summary.username)").font(.headline)
                }
            }
            .lineLimit(stacked ? 2 : 1)
            .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func numbers(_ summary: BoardSummary, stacked: Bool, pulsing: Bool) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 12))
        layout {
            rank(summary)
            if !stacked { Spacer(minLength: 8) }
            count(summary, alignment: stacked ? .leading : .trailing, pulsing: pulsing)
        }
    }

    /// "#3 of 6", or the trophy alone when there's no rank yet (or nobody to rank against).
    @ViewBuilder
    private func rank(_ summary: BoardSummary) -> some View {
        if let rank = summary.rank {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("#\(rank)")
                    .font(CommittedType.display(78, relativeTo: .largeTitle))
                    .displayTracking(78)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(rank)))
                    .animation(reduceMotion ? nil : .snappy, value: rank)
                    .overlay { RankBurst(trigger: bursts) }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("of \(summary.competitorCount)")
                    .font(CommittedType.numeral(20, relativeTo: .title3))
                    .foregroundStyle(Color.muted)
                    .fixedSize()
            }
        } else {
            TrophyMark(size: trophySize)
                .shadow(color: Color.lime.opacity(0.45), radius: 14)
        }
    }

    private func count(_ summary: BoardSummary, alignment: HorizontalAlignment, pulsing: Bool) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(summary.contributions?.formatted() ?? "—")
                .font(CommittedType.display(44, relativeTo: .largeTitle))
                .displayTracking(44)
                .foregroundStyle(Color.lime)
                .contentTransition(.numericText(value: Double(summary.contributions ?? 0)))
                .animation(reduceMotion ? nil : .snappy, value: summary.contributions)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Opacity-only pulse while refreshing. A repeating animation started with
                // withAnimation would also replay the number change and layout forever.
                .phaseAnimator(pulsing && !reduceMotion ? [1.0, 0.4] : [1.0]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 0.85) }
            Text("Contributions")
                .font(CommittedType.label)
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Color.muted)
        }
        .fixedSize()
    }

    @ViewBuilder
    private func footer(_ summary: BoardSummary) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                if let movement = summary.movementToday {
                    Label(movement > 0 ? "Up \(movement) today" : "Down \(-movement) today",
                          systemImage: movement > 0 ? "chevron.up" : "chevron.down")
                        .fontWeight(.semibold)
                        .foregroundStyle(movement > 0 ? Color.lime : Color.muted)
                }
                if let age = refreshAgeText(summary.lastUpdated, now: context.date) {
                    Text(age)
                } else if refresh.isRefreshing {
                    Text("Updating…")
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.muted)
        }
    }

    /// Your rank on one Window, so a Window switch never reads as a climb.
    private struct BurstKey: Equatable {
        let rank: Int?
        let window: ContributionWindow
    }

    private func refreshAgeText(_ lastUpdated: Date?, now: Date) -> String? {
        guard let lastUpdated else { return nil }
        let age = RelativeTimeFormatter.short(from: lastUpdated, to: now)
        return age == "just now" ? "Updated just now" : "Updated \(age)"
    }
}
