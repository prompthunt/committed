import Foundation

/// Helpers for turning a GitHub profile display name into the short form the hero card shows.
enum DisplayName {
    /// The first whitespace-separated token of a full name, or nil when there's nothing usable.
    /// "Addison Kowalski" → "Addison", "  Addison   Kowalski " → "Addison", "" / "   " / nil → nil.
    static func firstName(from fullName: String?) -> String? {
        guard let fullName else { return nil }
        let first = fullName
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init)
        return (first?.isEmpty == false) ? first : nil
    }
}
