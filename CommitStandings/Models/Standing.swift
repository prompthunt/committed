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

/// Result of fetching a competitor's standing — just the contributions count.
struct StandingCounts: Equatable, Sendable {
    var contributions: Int

    init(contributions: Int) {
        self.contributions = contributions
    }
}

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

    var dayCount: Int {
        switch self {
        case .daily: return 1
        case .weekly: return 7
        case .monthly: return 30
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .daily: return "today"
        case .weekly: return "the last 7 days"
        case .monthly: return "the last 30 days"
        }
    }

    func dateRange(asOf reference: Date, calendar: Calendar = .current) -> ClosedRange<Date>? {
        let today = calendar.startOfDay(for: reference)
        guard let earliest = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) else {
            return nil
        }
        return earliest...today
    }
}
