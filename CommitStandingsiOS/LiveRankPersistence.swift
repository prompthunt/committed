import Foundation

/// Live rank's settings on this iPhone.
struct LiveRankPreferences: Codable, Equatable, Sendable {
    /// nil until the person has decided. Without a relay that counts as on (phase 1); with a
    /// relay it counts as off until the disclosure is accepted.
    var isEnabled: Bool?
    var window: ContributionWindow = .daily
    /// Whether the person accepted the Committed relay disclosure. With a relay configured,
    /// Live rank is on only once this is true.
    var relayDisclosureAccepted: Bool?

    init(isEnabled: Bool? = nil, window: ContributionWindow = .daily, relayDisclosureAccepted: Bool? = nil) {
        self.isEnabled = isEnabled
        self.window = window
        self.relayDisclosureAccepted = relayDisclosureAccepted
    }
}

protocol LiveRankPersistence: Sendable {
    func loadPreferences() -> LiveRankPreferences
    func savePreferences(_ preferences: LiveRankPreferences)
    /// The state Live rank last derived (nil once it ends), for the app's extension and relay code.
    func saveLatestState(_ state: LiveRankState?)
    func loadLatestState() -> LiveRankState?
}

/// Stored in the App Group the app shares with its Live rank extension.
final class UserDefaultsLiveRankPersistence: LiveRankPersistence, @unchecked Sendable {
    static let appGroup = "group.com.addisonk.CommitStandings"
    static let preferencesKey = "liveRank.preferences"
    static let latestStateKey = "liveRank.latestState"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: UserDefaultsLiveRankPersistence.appGroup) ?? .standard) {
        self.defaults = defaults
    }

    func loadPreferences() -> LiveRankPreferences {
        defaults.data(forKey: Self.preferencesKey)
            .flatMap { try? JSONDecoder().decode(LiveRankPreferences.self, from: $0) } ?? LiveRankPreferences()
    }

    func savePreferences(_ preferences: LiveRankPreferences) {
        defaults.set(try? JSONEncoder().encode(preferences), forKey: Self.preferencesKey)
    }

    func saveLatestState(_ state: LiveRankState?) {
        defaults.set(state.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.latestStateKey)
    }

    func loadLatestState() -> LiveRankState? {
        defaults.data(forKey: Self.latestStateKey).flatMap { try? JSONDecoder().decode(LiveRankState.self, from: $0) }
    }
}

final class InMemoryLiveRankPersistence: LiveRankPersistence, @unchecked Sendable {
    private var preferences: LiveRankPreferences
    private var latest: LiveRankState?

    init(_ preferences: LiveRankPreferences = LiveRankPreferences()) {
        self.preferences = preferences
    }

    func loadPreferences() -> LiveRankPreferences { preferences }
    func savePreferences(_ preferences: LiveRankPreferences) { self.preferences = preferences }
    func saveLatestState(_ state: LiveRankState?) { latest = state }
    func loadLatestState() -> LiveRankState? { latest }
}
