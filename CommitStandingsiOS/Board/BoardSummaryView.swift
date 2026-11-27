import SwiftUI

/// You first, as the site's hero: your rank set huge, your Contributions for the Window in lime, your streak, today's movement,
/// the gap to pass the person ahead, and how long ago the numbers refreshed. People sync shows
/// under the card only while it's running or has failed. When your rank improves, squares burst
/// out of it. In 1st, 2nd or 3rd place on a board of four or more the card becomes a rank card
/// in the place's metal (`CardChrome`): the gold, silver or bronze trophy (`PodiumTrophy`) on top,
/// the Window's rank title and your place under it, then your Contributions and streak as chips.
///
/// Text on the card is white, soft, or lime, never muted. Every size follows Dynamic Type; at
/// accessibility sizes the numbers stack under your name and the rank stops growing at accessibility 2.
/// VoiceOver reads the card as one sentence (`BoardSummary.accessibilityDescription`).
struct BoardSummaryView: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(AuthModel.self) private var auth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var trophySize: CGFloat = 58
    /// The 1st–3rd trophy, at the top of the card.
    @ScaledMetric(relativeTo: .largeTitle) private var podiumTrophySize: CGFloat = 88
    @ScaledMetric(relativeTo: .footnote) private var podiumAvatarSize: CGFloat = 22
    /// Bumped each time your rank improves, to fire `RankBurst`.
    @State private var bursts = 0

    private var summary: BoardSummary? {
        BoardSummary.make(
            competitors: store.visibleCompetitors,
            standings: store.standings(for: store.selectedWindow),
            window: store.selectedWindow,
            displayName: auth.displayName,
            rankDelta: { [window = store.selectedWindow] in refresh.rankDelta(for: $0, in: window) },
            streak: { refresh.streak(for: $0) },
            lastUpdated: store.lastUpdated
        )
    }

    var body: some View {
        let summary = summary
        VStack(alignment: .leading, spacing: 10) {
            if let summary {
                card(summary)
            }
            RosterSyncNotice()
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
            if let podium = summary.podium {
                podiumBody(summary, podium: podium, stacked: stacked, pulsing: isRefreshingMine)
            } else {
                identity(summary, stacked: stacked)
                numbers(summary, stacked: stacked, pulsing: isRefreshingMine)
                footer(summary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardChrome(podium: summary.podium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityDescription)
        .accessibilityValue(refreshAgeText(summary.lastUpdated, now: .now) ?? "")
    }

    /// 1st, 2nd or 3rd, laid out like a rank card: the trophy up top and the one hero, the
    /// Window's rank title and your place under it, your name as a caption, then your
    /// Contributions and streak as equal chips. It's the only place the trophy art appears.
    @ViewBuilder
    private func podiumBody(_ summary: BoardSummary, podium: Podium, stacked: Bool, pulsing: Bool) -> some View {
        VStack(alignment: .center, spacing: 0) {
            PodiumTrophy(podium: podium, size: podiumTrophySize * (stacked ? 0.85 : 1))
            Text(summary.window.rankTitle)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(podium.metal[0])
                .padding(.top, 16)
            if let rank = summary.rank {
                Text("#\(rank)")
                    .font(CommittedType.display(52, relativeTo: .largeTitle))
                    .displayTracking(52)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(rank)))
                    .animation(reduceMotion ? nil : .snappy, value: rank)
                    .overlay { RankBurst(trigger: bursts) }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            HStack(spacing: 8) {
                AvatarView(username: summary.username, size: podiumAvatarSize)
                    .overlay { Circle().strokeBorder(podium.metal[1], lineWidth: 1.5) }
                Text(summary.firstName ?? summary.username)
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(.white)
                    .lineLimit(stacked ? 2 : 1)
                    .truncationMode(.middle)
            }
            .padding(.top, 12)
            podiumStats(summary, pulsing: pulsing)
                .padding(.top, 14)
            podiumAge(summary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    /// Contributions and streak as two chips of one size, side by side or stacked when they don't fit.
    private func podiumStats(_ summary: BoardSummary, pulsing: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { statChips(summary, pulsing: pulsing) }
            VStack(spacing: 8) { statChips(summary, pulsing: pulsing) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder
    private func statChips(_ summary: BoardSummary, pulsing: Bool) -> some View {
        HStack(spacing: 7) {
            ContributionGrid(size: 13, color: .lime)
            Text(summary.contributions?.formatted() ?? "—")
                .foregroundStyle(Color.lime)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(summary.contributions ?? 0)))
                .animation(reduceMotion ? nil : .snappy, value: summary.contributions)
                .phaseAnimator(pulsing && !reduceMotion ? [1.0, 0.4] : [1.0]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 0.85) }
            Text("Contributions").foregroundStyle(Color.soft)
        }
        .statChip()
        if StreakLabel.number(summary.streak) != nil {
            HStack(spacing: 7) {
                StreakBadge(streak: summary.streak, markSize: 13, relativeTo: .footnote, markColor: .lime)
                    .foregroundStyle(.white)
                Text("day streak")
                    .foregroundStyle(Color.soft)
                    .accessibilityHidden(true)  // the badge already says "12-day streak"
            }
            .statChip()
        }
    }

    /// How fresh the numbers are: tiny, under the stats.
    private func podiumAge(_ summary: BoardSummary) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let age = summary.lastUpdated.map { CoarseAge.compact(since: $0, now: context.date) }
                ?? (refresh.isRefreshing ? "Updating…" : nil)
            if let age {
                Text(age)
                    .font(.caption2)
                    .foregroundStyle(Color.soft)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func identity(_ summary: BoardSummary, stacked: Bool) -> some View {
        HStack(spacing: 10) {
            AvatarView(username: summary.username, size: avatarSize)
                .overlay { Circle().strokeBorder(Color.lime.opacity(0.6), lineWidth: 1.5) }
            VStack(alignment: .leading, spacing: 0) {
                if let firstName = summary.firstName {
                    Text(firstName).font(.headline)
                    Text("@\(summary.username)").font(.subheadline).foregroundStyle(Color.soft)
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
                    .foregroundStyle(Color.soft)
                    .fixedSize()
            }
            // Past accessibility 2 the rank alone would fill the first screen.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
                .eyebrow()
                .foregroundStyle(Color.soft)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .fixedSize()
    }

    @ViewBuilder
    private func footer(_ summary: BoardSummary) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let age = summary.lastUpdated.map { CoarseAge.compact(since: $0, now: context.date) }
                ?? (refresh.isRefreshing ? "Updating…" : nil)
            let stacked = dynamicTypeSize.isAccessibilitySize
            let news = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 14))
            // The news (your streak, today's movement), and how fresh the numbers are, small
            // and quiet in the bottom right corner.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                news {
                    // Your streak, written out: the mark in lime (it's yours, like the count above).
                    if StreakLabel.number(summary.streak) != nil {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            StreakBadge(streak: summary.streak, markSize: 14, relativeTo: .footnote, markColor: .lime)
                                .foregroundStyle(.white)
                            Text("day streak")
                                .accessibilityHidden(true)  // the badge already says "12-day streak"
                        }
                        .fontWeight(.semibold)
                    }
                    if let movement = summary.movementToday {
                        HStack(spacing: 4) {
                            Image(systemName: movement > 0 ? "chevron.up" : "chevron.down")
                                .imageScale(.small)
                            Text(movement > 0 ? "Up \(movement) today" : "Down \(-movement) today")
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(movement > 0 ? Color.lime : Color.soft)
                    }
                }
                .font(.footnote)
                Spacer(minLength: 8)
                if let age {
                    Text(age)
                        .font(.caption2)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(Color.soft)
        }
    }

    /// Your rank on one Window, so a Window switch never reads as a climb.
    private struct BurstKey: Equatable {
        let rank: Int?
        let window: ContributionWindow
    }

    private func refreshAgeText(_ lastUpdated: Date?, now: Date) -> String? {
        guard let lastUpdated else { return nil }
        return "Updated \(CoarseAge.text(since: lastUpdated, now: now))"
    }
}

/// The hero card's surface. Plain for everyone; for 1st–3rd a rank-card frame in the place's metal:
/// a bevelled edge that catches light top and bottom, and a soft wash of light falling from the
/// top edge. Everything stays inside the frame.
private struct CardChrome: ViewModifier {
    let podium: Podium?
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    func body(content: Content) -> some View {
        if let podium {
            content
                .background {
                    ZStack {
                        shape.fill(Color.tile)
                        shape.fill(RadialGradient(
                            colors: [podium.metal[0].opacity(0.20), podium.metal[1].opacity(0.06), .clear],
                            center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 340))
                        shape.fill(LinearGradient(
                            colors: [.clear, podium.metal[2].opacity(0.10)],
                            startPoint: UnitPoint(x: 0.5, y: 0.55), endPoint: .bottom))
                    }
                }
                .overlay { shape.strokeBorder(podium.edge, lineWidth: 3) }
                .clipShape(shape)
        } else {
            content
                .tileCard(cornerRadius: 22)
                .clipShape(shape)
        }
    }
}

private extension View {
    /// One of the podium card's stat chips: a soft capsule, one size for every stat.
    func statChip() -> some View {
        font(.footnote.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06), in: Capsule())
    }
}

private extension ContributionWindow {
    /// The rank's title on a podium card.
    var rankTitle: String {
        switch self {
        case .daily: "TODAY'S RANK"
        case .weekly: "7-DAY RANK"
        case .monthly: "30-DAY RANK"
        }
    }
}

/// The bundled 1st, 2nd or 3rd trophy. It springs in
/// when the card first shows it, and again if the place changes (reduced motion: no spring).
/// Decorative: VoiceOver gets the place from the card's sentence.
struct PodiumTrophy: View {
    let podium: Podium
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        Group {
            if let image = Self.image(named: podium.assetName) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 5)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(shown || reduceMotion ? 1 : 0.7)
        .opacity(shown || reduceMotion ? 1 : 0)
        .rotationEffect(.degrees(shown || reduceMotion ? 0 : -8))
        .id(podium)
        .onAppear {
            withAnimation(.spring(duration: 0.65, bounce: 0.38)) { shown = true }
        }
        .accessibilityHidden(true)
    }

    private static let cache = NSCache<NSString, UIImage>()

    private static func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let data = NSDataAsset(name: name)?.data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

private extension Podium {
    /// The metal, light to dark, for the frame, rank title and stat marks.
    var metal: [Color] {
        switch self {
        case .gold: [Color(red: 1.0, green: 0.88, blue: 0.5), Color(red: 0.96, green: 0.66, blue: 0.16), Color(red: 0.66, green: 0.42, blue: 0.06)]
        case .silver: [Color(red: 0.92, green: 0.96, blue: 1.0), Color(red: 0.6, green: 0.72, blue: 0.9), Color(red: 0.36, green: 0.46, blue: 0.66)]
        case .bronze: [Color(red: 0.97, green: 0.7, blue: 0.45), Color(red: 0.82, green: 0.48, blue: 0.22), Color(red: 0.5, green: 0.25, blue: 0.1)]
        }
    }

    /// The frame's edge: light catches the top and bottom, the sides fall into shadow.
    var edge: LinearGradient {
        LinearGradient(colors: [metal[0], metal[1], metal[2], metal[1], metal[0]], startPoint: .top, endPoint: .bottom)
    }
}

/// People sync, only when there's something to say: it's running, or it failed (with Retry). The
/// Board's freshness is the hero's "Updated …" line; People shows when people last synced.
/// On People it also names organizations left out because they restrict app access.
struct RosterSyncNotice: View {
    var showsRestricted = false
    @Environment(GitHubRoster.self) private var roster
    @Environment(RefreshCoordinator.self) private var refresh

    /// Whether People has a restricted-organization note to show.
    static func hasRestrictedNotice(_ roster: GitHubRoster) -> Bool {
        roster.snapshot?.restrictedNotice != nil
    }

    var body: some View {
        if roster.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(.soft)
                Text("Syncing people from GitHub…")
            }
            .font(.caption)
            .foregroundStyle(Color.muted)
            .accessibilityElement(children: .combine)
        } else if let error = roster.errorMessage {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warning)
                    Text("Couldn’t sync people")
                        .foregroundStyle(.white)
                    Text("·").foregroundStyle(Color.muted)
                    Button("Retry") { Task { await refresh.refreshAll(reason: .manual) } }
                        .fontWeight(.semibold)
                        .tint(.lime)
                        .disabled(refresh.isRefreshing)
                }
                Text(roster.snapshot == nil ? error : "\(error) Showing your last synced people.")
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
        } else if showsRestricted, let notice = roster.snapshot?.restrictedNotice {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lock.fill").foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
                Text(notice)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
        }
    }
}
