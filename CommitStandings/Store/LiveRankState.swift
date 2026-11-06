import Foundation

/// Live rank's content state: what the Dynamic Island and the Lock Screen show. It's the contract
/// between the iPhone app, its Live Activity extension, and the Committed relay
/// (`LiveRankAttributes.ContentState`), so its JSON shape is fixed by spec #39 and must match
/// `relay/src/liveRank.ts`. Dates are integer Unix seconds so the relay can encode them without
/// `JSONDecoder`'s reference-date default.
struct LiveRankState: Codable, Hashable, Sendable {
    /// The person ranked next to you, with their count for the Window and how they've moved today.
    struct Neighbor: Codable, Hashable, Sendable {
        var login: String
        var contributions: Int
        /// Their places moved since the day's baseline (+ up, − down), like yours. Today only;
        /// otherwise 0. Absent from older pushes and saved states, which decode it as 0.
        var movementToday: Int = 0
    }

    /// `ContributionWindow` raw value: "daily", "weekly", or "monthly".
    var window: String
    /// Your place. nil when your count hasn't loaded, or when nobody else is visible.
    var rank: Int?
    /// Everyone visible on your board, you included, with or without data.
    var competitorCount: Int
    /// Your count for the Window. nil (shown as a placeholder, never zero) until it loads.
    var contributions: Int?
    /// The person ranked directly above you, when you have a rank and they have data.
    var above: Neighbor?
    /// The person ranked directly below you, when you have a rank and they have data.
    var below: Neighbor?
    /// Places moved since the day's baseline (+ up, − down). Today only; otherwise 0.
    var movementToday: Int
    /// Unix seconds of the data, not of the update that carried it.
    var updatedAt: Int
}

extension LiveRankState.Neighbor {
    private enum CodingKeys: String, CodingKey { case login, contributions, movementToday }

    /// Tolerates a missing `movementToday` (added for #53), so a push from an older relay or a
    /// state an older build saved still decodes. Encoding stays synthesized and always writes it.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            login: try container.decode(String.self, forKey: .login),
            contributions: try container.decode(Int.self, forKey: .contributions),
            movementToday: try container.decodeIfPresent(Int.self, forKey: .movementToday) ?? 0
        )
    }
}

extension LiveRankState {
    /// How long after its data Live rank looks stale (dimmed, with the refresh age).
    static let staleInterval: TimeInterval = 20 * 60

    var contributionWindow: ContributionWindow? { ContributionWindow(rawValue: window) }

    /// When the data was fetched.
    var updatedDate: Date { Date(timeIntervalSince1970: TimeInterval(updatedAt)) }

    /// The Live Activity's stale date: 20 minutes after the data, not after the update.
    var staleDate: Date { updatedDate.addingTimeInterval(Self.staleInterval) }

    /// Contributions to pass the person ahead ("3 to pass alice"). You're first on your own
    /// board, so a tie puts you ahead: the gap itself is enough (at least 1). nil when nobody is
    /// ahead or your count hasn't loaded.
    ///
    /// Invariant: every producer lists you first. `derive` asserts it, and the relay enforces it
    /// on registration and on every cycle (`selfFirst` in `relay/src/ranking.ts`), so `above`
    /// always has strictly more than you and the `max(…, 1)` never hides a tie.
    var gapToPass: Int? {
        guard let above, let contributions else { return nil }
        return max(above.contributions - contributions, 1)
    }

    /// "3 to pass alice": `gapToPass` and who's ahead, as Live rank and the Board's hero show it.
    var passLine: String? {
        guard let gap = gapToPass, let above else { return nil }
        return "\(gap) to pass \(above.login)"
    }

    /// Said in place of a rank when there isn't one: nobody else on the board, or your count hasn't
    /// loaded yet. nil when there's a rank to show.
    var emptyStateLine: String? {
        if competitorCount <= 1 { return "Just you so far" }
        if contributions == nil { return "Waiting for your first count" }
        return nil
    }

    /// Tapping Live rank opens the Board on its Window.
    var boardURL: URL { DeepLink.board(window: contributionWindow).url }
}
