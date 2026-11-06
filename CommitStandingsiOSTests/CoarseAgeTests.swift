import Foundation
import Testing
@testable import CommitStandingsiOS

/// "Updated 4 min ago", "Synced 2 hr ago": freshness to the minute, never the second.
struct CoarseAgeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func age(_ seconds: TimeInterval) -> String {
        CoarseAge.text(since: now.addingTimeInterval(-seconds), now: now)
    }

    @Test func underAMinuteIsJustNow() {
        #expect(age(0) == "just now")
        #expect(age(59) == "just now")
        #expect(age(-30) == "just now")
    }

    @Test func minutesHoursAndDays() {
        #expect(age(60) == "1 min ago")
        #expect(age(4 * 60 + 8) == "4 min ago")
        #expect(age(59 * 60 + 59) == "59 min ago")
        #expect(age(3600) == "1 hr ago")
        #expect(age(5 * 3600 + 1800) == "5 hr ago")
        #expect(age(86_400) == "1 day ago")
        #expect(age(3 * 86_400) == "3 days ago")
    }
}
