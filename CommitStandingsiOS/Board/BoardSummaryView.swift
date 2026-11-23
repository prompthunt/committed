import SwiftUI

/// You first, as the site's hero: a folio ("01 · TODAY"), your rank set huge over a lit field of
/// contribution squares, your Contributions for the Window in lime, your streak, today's movement,
/// the gap to pass the person ahead, and how long ago the numbers refreshed. People sync shows
/// under the card only while it's running or has failed. When your rank improves, squares burst
/// out of it. In 1st, 2nd or 3rd place on a board of four or more, a gold, silver or bronze trophy
/// (`PodiumTrophy`) takes the card's corner, the only place that art appears.
///
/// Text on the card is white, soft, or lime, never muted: the field can sit under any of it
/// (`FieldTone.hero`, checked in `ThemeTests`). Every size follows Dynamic Type; at accessibility
/// sizes the numbers stack under your name and the rank stops growing at accessibility 2.
/// VoiceOver reads the card as one sentence (`BoardSummary.accessibilityDescription`).
struct BoardSummaryView: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(AuthModel.self) private var auth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 34
    @ScaledMetric(relativeTo: .largeTitle) private var trophySize: CGFloat = 58
    /// The 1st–3rd trophy, which sits beside your rank.
    @ScaledMetric(relativeTo: .largeTitle) private var podiumTrophySize: CGFloat = 152
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
            FolioRow(leading: Self.folio(summary.window), trailing: "Your rank")
            if let podium = summary.podium {
                podiumBody(summary, podium: podium, stacked: stacked, pulsing: isRefreshingMine)
            } else {
                identity(summary, stacked: stacked)
                numbers(summary, stacked: stacked, pulsing: isRefreshingMine)
            }
            footer(summary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            AnimatedSquareField(light: UnitPoint(x: 0.86, y: 0.4), reach: 0.7, cell: 15, tone: .hero)
                // Behind the numbers: away from your name, and faded out above the folio and
                // below the numbers, so the label and footer rows sit on the bare tile.
                .mask {
                    LinearGradient(colors: [.clear, .black.opacity(0.55), .black], startPoint: .leading, endPoint: .trailing)
                        .mask(LinearGradient(stops: [
                            .init(color: .clear, location: 0.1), .init(color: .black, location: 0.3),
                            .init(color: .black, location: 0.52), .init(color: .clear, location: 0.78),
                        ], startPoint: .top, endPoint: .bottom))
                }
        }
        .tileCard(cornerRadius: 22)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityDescription)
        .accessibilityValue(refreshAgeText(summary.lastUpdated, now: .now) ?? "")
    }

    /// 1st, 2nd or 3rd: the trophy takes the right of the card, as on the Share rank image, with
    /// your rank beside it and your Contributions under the rank. It's the only place the trophy
    /// art appears, so it stays special.
    @ViewBuilder
    private func podiumBody(_ summary: BoardSummary, podium: Podium, stacked: Bool, pulsing: Bool) -> some View {
        if stacked {
            VStack(alignment: .leading, spacing: 14) {
                identity(summary, stacked: true)
                PodiumTrophy(podium: podium, size: podiumTrophySize * 0.8)
                rank(summary)
                podiumCount(summary, pulsing: pulsing)
            }
        } else {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 12) {
                    // Leave the trophy its corner: a long name truncates before it runs under it.
                    identity(summary, stacked: false)
                        .padding(.trailing, podiumTrophySize * 0.7)
                    rank(summary)
                    podiumCount(summary, pulsing: pulsing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PodiumTrophy(podium: podium, size: podiumTrophySize)
                    .offset(x: 14, y: -8)
            }
        }
    }

    /// "62 CONTRIBUTIONS" in lime under the rank, as on the Share rank image.
    private func podiumCount(_ summary: BoardSummary, pulsing: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(summary.contributions?.formatted() ?? "—")
                .font(CommittedType.display(34, relativeTo: .title))
                .displayTracking(34)
                .foregroundStyle(Color.lime)
                .contentTransition(.numericText(value: Double(summary.contributions ?? 0)))
                .animation(reduceMotion ? nil : .snappy, value: summary.contributions)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .phaseAnimator(pulsing && !reduceMotion ? [1.0, 0.4] : [1.0]) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 0.85) }
            Text("Contributions")
                .eyebrow()
                .foregroundStyle(Color.soft)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
            let age = refreshAgeText(summary.lastUpdated, now: context.date) ?? (refresh.isRefreshing ? "Updating…" : nil)
            let news = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 14))
            // The news (your streak, movement, the gap to pass), then how fresh the numbers are.
            VStack(alignment: .leading, spacing: 4) {
                news {
                    // Your streak: the mark in lime (it's yours, like the count above), the number white.
                    StreakBadge(streak: summary.streak, markSize: 14, relativeTo: .footnote, markColor: .lime)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    if let movement = summary.movementToday {
                        HStack(spacing: 4) {
                            Image(systemName: movement > 0 ? "chevron.up" : "chevron.down")
                                .imageScale(.small)
                            Text(movement > 0 ? "Up \(movement) today" : "Down \(-movement) today")
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(movement > 0 ? Color.lime : Color.soft)
                    }
                    if let passLine = summary.passLine {
                        Text(passLine)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.lime)
                            .monospacedDigit()
                    }
                }
                if let age { Text(age) }
            }
            .font(.footnote)
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

    /// "01 · TODAY": the Window's place in the switch, as the site numbers its cards.
    static func folio(_ window: ContributionWindow) -> String {
        let number = (ContributionWindow.allCases.firstIndex(of: window) ?? 0) + 1
        return String(format: "%02d · %@", number, window.shortTitle)
    }
}

/// The bundled 1st, 2nd or 3rd trophy over a soft glow in the metal's own colour. It springs in
/// when the card first shows it, and again if the place changes (reduced motion: no spring).
/// Decorative: VoiceOver gets the place from the card's sentence.
struct PodiumTrophy: View {
    let podium: Podium
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            RadialGradient(colors: [podium.glow.opacity(0.42), podium.glow.opacity(0)],
                           center: .center, startRadius: 0, endRadius: size * 0.62)
                .frame(width: size * 1.3, height: size * 1.3)
            if let image = Self.image(named: podium.assetName) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
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
    /// The glow behind the trophy: the metal's own light.
    var glow: Color {
        switch self {
        case .gold: Color(red: 1.0, green: 0.78, blue: 0.25)
        case .silver: Color(red: 0.72, green: 0.82, blue: 0.95)
        case .bronze: Color(red: 0.86, green: 0.52, blue: 0.26)
        }
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
