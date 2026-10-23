import SwiftUI

enum AvatarColor {
    /// Deterministic 1–2 character initials from a username.
    static func initials(for username: String) -> String {
        let clean = username.replacingOccurrences(of: "-", with: " ")
        let parts = clean.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }
        return String(username.prefix(2)).uppercased()
    }

    /// Deterministic color picked from a palette by hashing the username.
    /// Uses a stable UTF-8 byte sum rather than `Hasher`, whose seed is
    /// randomized per process and would make avatar colors flicker between
    /// app launches.
    static func color(for username: String) -> Color {
        let palette: [Color] = [
            .blue, .indigo, .purple, .pink, .red,
            .orange, .yellow, .green, .mint, .teal, .cyan
        ]
        var sum: UInt64 = 0xcbf29ce484222325 // FNV-1a offset basis
        for byte in username.utf8 {
            sum ^= UInt64(byte)
            sum = sum &* 0x100000001b3        // FNV-1a prime
        }
        let idx = Int(sum % UInt64(palette.count))
        return palette[idx]
    }
}
