import Foundation

/// A calendar month as GitHub's civil days name it (`"2026-10-…"`), so a month's days are the same
/// in every time zone. The person view draws this month's days over last month's.
struct CalendarMonth: Hashable, Sendable {
    let year: Int
    /// 1 (January) through 12.
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// The month containing `date` in `calendar` (the device's, for "this month").
    init(containing date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1)
    }

    var previous: CalendarMonth {
        month == 1 ? CalendarMonth(year: year - 1, month: 12) : CalendarMonth(year: year, month: month - 1)
    }

    /// 28 to 31.
    var dayCount: Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// "October", in English like the rest of the app.
    var name: String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August",
                     "September", "October", "November", "December"]
        return names[(month - 1) % 12]
    }
}
