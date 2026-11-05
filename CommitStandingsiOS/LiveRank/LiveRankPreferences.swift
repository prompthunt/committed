import Foundation

/// Live rank's settings on this iPhone.
struct LiveRankPreferences: Codable, Equatable, Sendable {
    /// nil until the person has chosen, which phase 1 treats as on. The relay's disclosure (#45)
    /// asks before the first enable, so "never chosen" stays distinguishable from "on".
    var isEnabled: Bool?
    var window: ContributionWindow = .daily
}

protocol LiveRankPreferenceStoring: AnyObject {
    func load() -> LiveRankPreferences
    func save(_ preferences: LiveRankPreferences)
}

final class UserDefaultsLiveRankPreferences: LiveRankPreferenceStoring {
    private let defaults: UserDefaults
    private let key = "liveRank.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LiveRankPreferences {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LiveRankPreferences.self, from: $0) }
            ?? LiveRankPreferences()
    }

    func save(_ preferences: LiveRankPreferences) {
        defaults.set(try? JSONEncoder().encode(preferences), forKey: key)
    }
}

final class InMemoryLiveRankPreferences: LiveRankPreferenceStoring {
    private var preferences: LiveRankPreferences

    init(_ preferences: LiveRankPreferences = LiveRankPreferences()) {
        self.preferences = preferences
    }

    func load() -> LiveRankPreferences { preferences }
    func save(_ preferences: LiveRankPreferences) { self.preferences = preferences }
}
