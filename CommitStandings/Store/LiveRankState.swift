import Foundation

/// Live rank's content state: what the Dynamic Island and the Lock Screen show. It is the
/// contract between the iPhone app, its Live Activity, and the Committed relay
/// (`LiveRankAttributes.ContentState`), so its JSON shape is fixed by spec #39. Dates are
/// integer Unix seconds so the relay can encode them without `JSONDecoder`'s reference date.
/// Synthesized `Codable` omits nil keys and decodes a missing key and `null` the same.
struct LiveRankState: Codable, Hashable, Sendable {
    /// The person ranked next to you, with their count for the Window.
    struct Neighbor: Codable, Hashable, Sendable {
        var login: String
        var contributions: Int
    }

    /// `ContributionWindow` raw value: "daily", "weekly", or "monthly".
    var window: String
    /// Your place. nil when your count hasn't loaded, or when nobody else is visible.
    var rank: Int?
    /// Everyone visible on your board, including you, with or without data.
    var competitorCount: Int
    /// Your count for the Window; nil (a placeholder, never zero) until it loads.
    var contributions: Int?
    /// The person ranked directly above you.
    var above: Neighbor?
    /// The person ranked directly below you, if they have data.
    var below: Neighbor?
    /// Places moved since the day's baseline (+ up, − down). Today only; otherwise 0.
    var movementToday: Int
    /// Unix seconds of the oldest count shown (yours, above, below), not of the update that
    /// carried it, so a stale count never looks fresh.
    var updatedAt: Int
}

extension LiveRankState {
    /// How long after its data Live rank looks stale (dimmed, with the refresh age).
    static let staleInterval: TimeInterval = 20 * 60

    var contributionWindow: ContributionWindow? { ContributionWindow(rawValue: window) }

    var updatedDate: Date { Date(timeIntervalSince1970: TimeInterval(updatedAt)) }

    /// The Live Activity's stale date: 20 minutes after the data, not after the update.
    var staleDate: Date { updatedDate.addingTimeInterval(Self.staleInterval) }

    /// How close the stale date may get before a heartbeat moves it (the relay's
    /// `HEARTBEAT_LEAD_SECONDS`).
    static let heartbeatLead: TimeInterval = 10 * 60

    /// The same numbers, apart from `updatedAt` (which advances with every fetch).
    func sameContent(as other: LiveRankState) -> Bool {
        var other = other
        other.updatedAt = updatedAt
        return self == other
    }

    /// Whether `next` should replace this state on screen: its numbers changed, or this one's
    /// stale date is near and `next` moves it later (a heartbeat). Matches the relay's rule.
    func shouldUpdate(to next: LiveRankState, now: Date) -> Bool {
        !sameContent(as: next)
            || (now >= staleDate.addingTimeInterval(-Self.heartbeatLead) && next.staleDate > staleDate)
    }

    /// Contributions you need to pass the person ahead ("3 to pass alice"). One more than the
    /// gap, since a tie keeps them ahead; nil when nobody is ahead or your count isn't loaded.
    var gapToPass: Int? {
        guard let above, let contributions else { return nil }
        return max(above.contributions - contributions + 1, 1)
    }

    /// Tapping Live rank opens the board on its Window.
    var boardURL: URL {
        var components = URLComponents()
        components.scheme = "committed"
        components.host = "board"
        components.queryItems = [URLQueryItem(name: "window", value: window)]
        return components.url!
    }
}
