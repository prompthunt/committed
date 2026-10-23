import Foundation

struct Competitor: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var username: String
    var isSelf: Bool

    init(id: UUID = UUID(), username: String, isSelf: Bool) {
        self.id = id
        self.username = username
        self.isSelf = isSelf
    }
}

enum UsernameNormalization {
    /// Strip leading `@`, trim whitespace, lowercase. Returns nil for empty
    /// strings or strings containing characters GitHub does not allow.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("@") { s.removeFirst() }
        s = s.lowercased()
        guard !s.isEmpty else { return nil }
        // GitHub usernames: alphanumerics + hyphens, no consecutive hyphens, 1–39 chars.
        // Keep validation pragmatic; let the server reject anything malformed.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard s.count <= 39 else { return nil }
        guard !s.hasPrefix("-"), !s.hasSuffix("-") else { return nil }
        guard !s.contains("--") else { return nil }
        return s
    }
}
