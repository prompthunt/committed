import Foundation

/// One Competitor's daily contribution counts, as GitHub's calendar gave them, and the time zone
/// they were read in. Every Window total comes from here. It's pure: each function takes the date
/// to answer for and uses this history's own calendar, never the clock or the machine's time zone.
/// Later tickets add streaks and active days beside `total`; the Windows core has
/// the same functions in `windows/core/src/history.rs`.
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
    /// each first and last day: today and the 6 or 29 days before it for the trailing Windows, and
    /// the 1st of the month through today for This month (so it resets on the 1st).
    func days(in window: ContributionWindow, asOf reference: Date) -> ClosedRange<Date> {
        let calendar = calendar
        let today = calendar.startOfDay(for: reference)
        let first: Date?
        switch window {
        case .daily: first = today
        case .weekly: first = calendar.date(byAdding: .day, value: -6, to: today)
        case .monthly: first = calendar.date(byAdding: .day, value: -29, to: today)
        case .month: first = calendar.dateInterval(of: .month, for: today)?.start
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
