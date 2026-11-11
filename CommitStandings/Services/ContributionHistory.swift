import Foundation

/// One Competitor's daily contribution counts, as GitHub's calendar gave them, and the time zone
/// they were read in. Every Window total comes from here. It's pure: each function takes the date
/// to answer for and uses this history's own calendar, never the clock or the machine's time zone.
/// Window and month totals, streaks and trolling days all come from it; the Windows core has the
/// same functions in `windows/core/src/history.rs`.
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

    /// Contributions in `window` as of `reference`, over `days(in:asOf:)`. Later days never count.
    func total(for window: ContributionWindow, asOf reference: Date) -> Int {
        let range = days(in: window, asOf: reference)
        return total(from: range.lowerBound, through: range.upperBound)
    }

    /// The days `window` covers as of `reference`, in this history's time zone, as the start of
    /// each first and last day: today, or today and the 6 or 29 days before it.
    func days(in window: ContributionWindow, asOf reference: Date) -> ClosedRange<Date> {
        let calendar = calendar
        let today = calendar.startOfDay(for: reference)
        let first: Date?
        switch window {
        case .daily: first = today
        case .weekly: first = calendar.date(byAdding: .day, value: -6, to: today)
        case .monthly: first = calendar.date(byAdding: .day, value: -29, to: today)
        }
        return (first ?? today)...today
    }

    /// Contributions from the day containing `first` through the day containing `last`,
    /// inclusive, in this history's time zone. Days the calendar doesn't have count as nothing.
    func total(from first: Date, through last: Date) -> Int {
        let calendar = calendar
        let end = calendar.startOfDay(for: last)
        var day = calendar.startOfDay(for: first)
        var total = 0
        while day <= end {
            total += days[Self.key(for: day, in: calendar)] ?? 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    /// The biggest trolling day `window` covers as of `reference`, if any (see `TrollCheck`). Each
    /// day is judged only against this calendar's days before it, so every device and Window agree
    /// on the same day; it stays on a longer Window until the day leaves it.
    func burst(for window: ContributionWindow, asOf reference: Date) -> Burst? {
        let calendar = calendar
        let range = days(in: window, asOf: reference)
        let first = Self.key(for: range.lowerBound, in: calendar)
        let last = Self.key(for: range.upperBound, in: calendar)
        // "YYYY-MM-DD" keys sort in date order.
        let ordered = days.sorted { $0.key < $1.key }
        var biggest: Burst?
        for (index, entry) in ordered.enumerated()
        where entry.key >= first && entry.key <= last && entry.value > TrollCheck.floor {
            let usual = TrollCheck.usualBigDay(ordered[..<index].map(\.value))
            guard TrollCheck.isTrolling(count: entry.value, usual: usual), entry.value > (biggest?.count ?? 0),
                  let day = Self.date(forKey: entry.key, in: calendar) else { continue }
            biggest = Burst(day: day, count: entry.value, usual: usual)
        }
        return biggest
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

    /// The longest run of consecutive days with a contribution anywhere in the calendar through
    /// today (about the past year), in this history's time zone. Days after today never count, and
    /// a day the calendar doesn't have breaks a run, as a zero does. The Windows core's
    /// `longest_streak` follows the same rules.
    func longestStreak(asOf reference: Date) -> Int {
        guard let earliest = days.keys.min() else { return 0 }
        let calendar = calendar
        var day = calendar.startOfDay(for: reference)
        var run = 0
        var longest = 0
        // Back from today to the calendar's first day; bounded so a malformed key can't loop long.
        for _ in 0..<Self.maxCalendarSpan {
            let key = Self.key(for: day, in: calendar)
            guard key >= earliest else { break }
            if (days[key] ?? 0) > 0 {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return longest
    }

    /// Ten years of days: far more than GitHub's calendar (53 weeks) ever covers.
    private static let maxCalendarSpan = 3_660

    /// The `"YYYY-MM-DD"` key for the day containing `date` in `calendar`.
    static func key(for date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return key(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// The start of the `"YYYY-MM-DD"` day in `calendar`, or nil for a malformed key.
    static func date(forKey key: String, in calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func key(year: Int, month: Int, day: Int) -> String {
        "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2))"
    }

    private static func padded(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
