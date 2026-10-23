import Foundation

protocol CompetitorPersistence: Sendable {
    func load() -> [Competitor]
    func save(_ competitors: [Competitor])
}

final class UserDefaultsCompetitorPersistence: CompetitorPersistence, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "competitors.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [Competitor] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Competitor].self, from: data)) ?? []
    }

    func save(_ competitors: [Competitor]) {
        if let data = try? JSONEncoder().encode(competitors) {
            defaults.set(data, forKey: key)
        }
    }
}

final class InMemoryCompetitorPersistence: CompetitorPersistence, @unchecked Sendable {
    private var storage: [Competitor] = []
    func load() -> [Competitor] { storage }
    func save(_ competitors: [Competitor]) { storage = competitors }
}

// MARK: - Standings snapshot

/// Durable cache of the last loaded standings so a relaunch shows numbers immediately
/// (then refreshes in the background) instead of a cold, blank board every time.
protocol StandingsSnapshotPersistence: Sendable {
    func load() -> [Standing]
    func save(_ standings: [Standing])
}

final class UserDefaultsStandingsSnapshotPersistence: StandingsSnapshotPersistence, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "standings.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [Standing] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Standing].self, from: data)) ?? []
    }

    func save(_ standings: [Standing]) {
        if let data = try? JSONEncoder().encode(standings) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Default for tests/previews and any caller that hasn't opted into durable storage:
/// keeps the snapshot only for the lifetime of this instance, so suites stay isolated.
final class InMemoryStandingsSnapshotPersistence: StandingsSnapshotPersistence, @unchecked Sendable {
    private var storage: [Standing] = []
    func load() -> [Standing] { storage }
    func save(_ standings: [Standing]) { storage = standings }
}

// MARK: - Per-account leaderboard visibility

protocol HiddenPeoplePersistence: Sendable {
    func load() -> [String: Set<String>]
    func save(_ hiddenByAccount: [String: Set<String>])
}

final class UserDefaultsHiddenPeoplePersistence: HiddenPeoplePersistence, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "hiddenPeopleByAccount.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [String: Set<String>] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Set<String>].self, from: data)) ?? [:]
    }

    func save(_ hiddenByAccount: [String: Set<String>]) {
        guard let data = try? JSONEncoder().encode(hiddenByAccount) else { return }
        defaults.set(data, forKey: key)
    }
}

final class InMemoryHiddenPeoplePersistence: HiddenPeoplePersistence, @unchecked Sendable {
    private var storage: [String: Set<String>] = [:]
    func load() -> [String: Set<String>] { storage }
    func save(_ hiddenByAccount: [String: Set<String>]) { storage = hiddenByAccount }
}
