import Foundation

/// Live rank's settings on this iPhone.
struct LiveRankPreferences: Codable, Equatable, Sendable {
    /// nil until the person has chosen, which phase 1 treats as on. With a relay, Live rank stays
    /// off until the disclosure is accepted.
    var isEnabled: Bool?
    var window: ContributionWindow = .daily
    /// The person accepted the Committed relay disclosure (what the relay receives). Asked once,
    /// before Live rank first turns on with a relay.
    var relayDisclosureAccepted = false

    init(isEnabled: Bool? = nil, window: ContributionWindow = .daily, relayDisclosureAccepted: Bool = false) {
        self.isEnabled = isEnabled
        self.window = window
        self.relayDisclosureAccepted = relayDisclosureAccepted
    }

    // Settings saved before the relay existed have no `relayDisclosureAccepted`.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
        window = try container.decodeIfPresent(ContributionWindow.self, forKey: .window) ?? .daily
        relayDisclosureAccepted = try container.decodeIfPresent(Bool.self, forKey: .relayDisclosureAccepted) ?? false
    }
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
