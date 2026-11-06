import Foundation

/// How long ago, to the minute: "just now", "4 min ago", "2 hr ago", "3 days ago". The Board's
/// "Updated …" and People's "Synced …" use it, so neither ever counts seconds.
enum CoarseAge {
    static func text(since date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        let minutes = Int(elapsed / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
}
