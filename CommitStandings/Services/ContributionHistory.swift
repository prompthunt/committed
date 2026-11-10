import Foundation

/// One Competitor's daily contribution counts, as GitHub's calendar gave them, and the time zone
/// they were read in. Every Window total comes from here. It's pure: each function takes the date
/// to answer for and uses this history's own calendar, never the clock or the machine's time zone.
/// Later tickets add month totals and active days beside `total` and `currentStreak`; the
/// Windows core has the same functions in `windows/core/src/history.rs`.
///
/// Days are GitHub's civil dates (`data-date="YYYY-MM-DD"`), kept as written. A day missing from
/// the calendar is unknown, never a zero; a person with no history at all is "no history yet".
struct ContributionHistory: Codable, Equatable, Sendable {
    /// `"YYYY-MM-DD"` → that day's contributions.
    var days: [String: Int]
    /// The identifier of the time zone the days were read in, which decides which day is today.
    var timeZoneIdentifier: String

    init(days: [String: Int], timeZone: TimeZone) {
        self.days = days
        self.timeZoneIdentifier = timeZone.identifier
    }

    private enum CodingKeys: String, CodingKey {
        case days
        case timeZoneIdentifier = "timeZone"
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .gmt }

    /// Gregorian, in this history's time zone.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Contributions in `window` as of `reference`: today (in this history's time zone) and the
    /// `window.dayCount - 1` days before it. Later days never count.
    func total(for window: ContributionWindow, asOf reference: Date) -> Int {
        let calendar = calendar
        let today = calendar.startOfDay(for: reference)
        var total = 0
        for offset in 0..<window.dayCount {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            total += days[Self.key(for: day, in: calendar)] ?? 0
        }
        return total
    }

    /// Days in a row with at least one contribution as of `reference`, counted back from today
    /// (in this history's time zone). While today has none yet, including when the calendar doesn't
    /// reach today, the run counts back from yesterday instead, so a streak stays alive until today
    /// ends. 0 when yesterday and today are both empty. Days after today never count, and the count
    /// stops at the calendar's first day: a run that long can't be seen further back.
    func currentStreak(asOf reference: Date) -> Int {
        let calendar = calendar
        let today = calendar.startOfDay(for: reference)
        var day = today
        if (days[Self.key(for: today, in: calendar)] ?? 0) <= 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            day = yesterday
        }
        var streak = 0
        // Bounded by the calendar's length, so a malformed calendar can't loop forever.
        while streak < days.count, (days[Self.key(for: day, in: calendar)] ?? 0) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// The `"YYYY-MM-DD"` key for the day containing `date` in `calendar`.
    static func key(for date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return key(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    static func key(year: Int, month: Int, day: Int) -> String {
        "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2))"
    }

    private static func padded(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
