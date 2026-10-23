import Foundation

enum RelativeTimeFormatter {
    static func short(from earlier: Date, to later: Date) -> String {
        let elapsed = max(0, later.timeIntervalSince(earlier))
        if elapsed < 60 { return "just now" }
        let minutes = Int(elapsed / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(elapsed / 3600)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(elapsed / 86_400)
        return "\(days)d ago"
    }
}
