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

    var id: String { username }

    init(
        username: String,
        contributions: Int,
        window: ContributionWindow,
        lastUpdated: Date,
        state: LoadState
    ) {
        self.username = username
        self.contributions = contributions
        self.window = window
        self.lastUpdated = lastUpdated
        self.state = state
    }
}

/// Result of fetching a competitor's standing: the Window's contributions count and, from the
/// real client, the daily counts it was worked out from. Stubs may leave `history` nil.
struct StandingCounts: Equatable, Sendable {
    var contributions: Int
    var history: ContributionHistory?

    init(contributions: Int, history: ContributionHistory? = nil) {
        self.contributions = contributions
        self.history = history
    }
}

/// The time range Contributions are counted over. Today, 7 days and 30 days are trailing; This
/// month is the local calendar month so far and resets to zero on the 1st. Raw values are saved
/// (settings, caches, Live rank, the relay), so 30 days stays `"monthly"` and This month is
/// `"month"`. Which days each one covers is `ContributionHistory.days(in:asOf:)`.
enum ContributionWindow: String, CaseIterable, Identifiable, Codable, Sendable {
    case daily
    case weekly
    case monthly
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .month: return "This month"
        }
    }

    var shortTitle: String {
        switch self {
        case .daily: return "Today"
        case .weekly: return "7 days"
        case .monthly: return "30 days"
        case .month: return "This month"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .daily: return "today"
        case .weekly: return "the last 7 days"
        case .monthly: return "the last 30 days"
        case .month: return "this month"
        }
    }

    /// Whether the board shows today's movement chevrons on this Window: Today, and This month
    /// (each measured from the day's first ranking). The trailing 7 and 30 days barely move hour to
    /// hour.
    var showsTodaysMovement: Bool {
        self == .daily || self == .month
    }

    /// "Day 10 of 30" on This month: the day of the month as of `reference` in `calendar` (the
    /// device's), and how many days the month has. nil on the other Windows.
    func dayOfMonth(asOf reference: Date, calendar: Calendar = .current) -> String? {
        guard self == .month,
              let length = calendar.range(of: .day, in: .month, for: reference)?.count else { return nil }
        return "Day \(calendar.component(.day, from: reference)) of \(length)"
    }
}
