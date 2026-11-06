import SwiftUI

/// The person above you, you, and the person below (whichever exist), drawn with the board's own
/// `StandingRow` (never forked): `#rank`, avatar, login, the "you" badge, today's chevron, the
/// count, and the squares glyph. The expanded Dynamic Island and the Lock Screen show these; both
/// are capped at about 160 pt, so the full board doesn't fit.
///
/// Avatars come from the App Group (`AvatarCache`): the app saves them on each refresh, since this
/// process can't load network images. Someone without a saved avatar gets initials.
struct LiveRankRows: View {
    let state: LiveRankState
    /// Your login, from the activity's attributes (the content state doesn't carry it).
    let selfLogin: String
    @Environment(\.liveRankIsStale) private var isStale

    struct Row: Equatable {
        let rank: Int
        let login: String
        let contributions: Int
        let movement: Int
        let isSelf: Bool
    }

    /// Empty without a rank: then there's nobody to stand between (see `emptyStateLine`).
    static func rows(_ state: LiveRankState, selfLogin: String) -> [Row] {
        guard let rank = state.rank, let contributions = state.contributions else { return [] }
        var rows: [Row] = []
        // Ranks are consecutive (`Ranking.order`), so your neighbors sit at rank ± 1.
        if let above = state.above {
            rows.append(Row(rank: rank - 1, login: above.login, contributions: above.contributions,
                            movement: above.movementToday, isSelf: false))
        }
        rows.append(Row(rank: rank, login: selfLogin, contributions: contributions,
                        movement: state.movementToday, isSelf: true))
        if let below = state.below {
            rows.append(Row(rank: rank + 1, login: below.login, contributions: below.contributions,
                            movement: below.movementToday, isSelf: false))
        }
        return rows
    }

    var body: some View {
        let rows = Self.rows(state, selfLogin: selfLogin)
        // Shaded against the busiest row shown, as the board shades against its leader.
        let busiest = rows.map(\.contributions).max() ?? 0
        let window = state.contributionWindow ?? .daily
        // Room between rows, so your highlighted row stands clear of its neighbors.
        VStack(spacing: 6) {
            ForEach(rows, id: \.rank) { row in
                StandingRow(
                    rank: row.rank,
                    competitor: Competitor(username: row.login, isSelf: row.isSelf),
                    standing: Standing(username: row.login, contributions: row.contributions, window: window,
                                       lastUpdated: state.updatedDate, state: .loaded),
                    window: window,
                    maxContributions: busiest,
                    rankDelta: row.movement
                )
            }
        }
        // Names and rivals' counts: white, stepping down to soft when stale.
        .foregroundStyle(isStale ? Color.soft : Color.white)
        .environment(\.standingRowStyle, .liveRank(stale: isStale))
        .environment(\.avatarFallbackStyle, .committed)
        // Never try the network here: it can't load, and AsyncImage would only show initials.
        .environment(\.loadsGitHubAvatars, false)
    }
}

extension StandingRowStyle {
    /// The board's iPhone row (`StandingRowStyle.committed`), compact enough for three rows and the
    /// pass line inside Live rank's height. Stale steps colors down (lime to deep lime) rather than
    /// fading them, like the rest of Live rank.
    static func liveRank(stale: Bool) -> StandingRowStyle {
        let accent: Color = stale ? .limeDeep : .lime
        return StandingRowStyle(
            rankFont: CommittedType.numeral(13, relativeTo: .footnote),
            rankColor: .muted,
            rankWidthScale: 1.1,
            nameFont: .subheadline,
            selfNameFont: .subheadline.weight(.semibold),
            countFont: CommittedType.numeral(16, relativeTo: .subheadline),
            selfCountFont: CommittedType.display(16, relativeTo: .subheadline),
            selfCountColor: accent,
            avatarSize: 22,
            spacing: 8,
            horizontalPadding: 10,
            verticalPadding: 4,
            accent: accent,
            badgeFont: .caption2.weight(.bold),
            badgeForeground: .onLime,
            badgeFillOpacity: 1,
            selfFillOpacity: 0.08,
            selfStrokeOpacity: 0.32,
            cornerRadius: 10,
            movementUpColor: accent,
            movementDownColor: stale ? .muted : .soft,
            movementFont: .caption2.weight(.heavy),
            squares: .shadedSymbol(Color.rowGlyphs)
        )
    }
}
