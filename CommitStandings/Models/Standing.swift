import Foundation

enum LoadState: Equatable, Codable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// One competitor's standing for a window. The sole metric is the GitHub contributions
/// count (the green-square total). Decodes leniently: an older persisted snapshot that
/// still carries removed fields (commits/locChanged/…) decodes fine — synthesized Codable
/// ignores unknown keys — so updating from a multi-metric build doesn't crash on launch.
struct Standing: Identifiable, Equatable, Codable {
    var username: String
    var contributions: Int
    var window: ContributionWindow
    var lastUpdated: Date
    var state: LoadState
    /// The biggest trolling day in the window, if any (see `TrollCheck`). The row marks it with
    /// the troll face; ranking ignores it. Older snapshots without it decode as nil.
    var burst: Burst?

    var id: String { username }

    init(
        username: String,
        contributions: Int,
        window: ContributionWindow,
        lastUpdated: Date,
        state: LoadState,
        burst: Burst? = nil
    ) {
        self.username = username
        self.contributions = contributions
        self.window = window
        self.lastUpdated = lastUpdated
        self.state = state
        self.burst = burst
    }
}

/// One day far above someone's usual: more than `TrollCheck.multiple` times their usual big day
/// and over `TrollCheck.floor`. Committed calls it trolling and marks the row; it doesn't change
/// the count or the rank.
struct Burst: Equatable, Codable, Sendable {
    var day: Date
    var count: Int
    /// Their usual big day before it: the count 9 in 10 of their earlier active days stay under.
    var usual: Int

    /// How many times their usual big day, rounded down; nil when they had no history.
    var multiple: Int? {
        usual > 0 ? count / usual : nil
    }
}

/// Result of fetching a competitor's standing: the Window's contributions count, the Window's
/// biggest trolling day when there is one and, from the real client, the daily counts both were
/// worked out from. Stubs may leave `history` nil.
struct StandingCounts: Equatable, Sendable {
    var contributions: Int
    var history: ContributionHistory?
    var burst: Burst?

    init(contributions: Int, history: ContributionHistory? = nil, burst: Burst? = nil) {
        self.contributions = contributions
        self.history = history
        self.burst = burst
    }

    /// `window`'s total and trolling day as of `reference`, both from `history`.
    init(history: ContributionHistory, window: ContributionWindow, asOf reference: Date) {
        self.init(
            contributions: history.total(for: window, asOf: reference),
            history: history,
            burst: history.burst(for: window, asOf: reference)
        )
    }
}

/// The time range Contributions are counted over: today, or the trailing 7 or 30 days. Raw values
/// are saved (settings, caches, Live rank, the relay), so 30 days stays `"monthly"`. Which days
/// each one covers is `ContributionHistory.days(in:asOf:)`.
enum ContributionWindow: String, CaseIterable, Identifiable, Codable, Sendable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var shortTitle: String {
        switch self {
        case .daily: return "Today"
        case .weekly: return "7 days"
        case .monthly: return "30 days"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .daily: return "today"
        case .weekly: return "the last 7 days"
        case .monthly: return "the last 30 days"
        }
    }

    /// Whether the board shows today's movement chevrons on this Window: Today only, measured from
    /// the day's first ranking. The trailing 7 and 30 days barely move hour to hour.
    var showsTodaysMovement: Bool {
        self == .daily
    }
}
