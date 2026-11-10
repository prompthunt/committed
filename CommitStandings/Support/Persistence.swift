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

// MARK: - Daily counts

/// Each Competitor's daily counts (`ContributionHistory`), keyed by username: one calendar per
/// person, not per Window. Kept apart from `standings.v1`, which decodes all-or-nothing, so a
/// cache from before daily counts were kept still loads; nothing saved means "no history yet".
protocol ContributionHistoryPersistence: Sendable {
    func load() -> [String: ContributionHistory]
    func save(_ histories: [String: ContributionHistory])
}

/// A JSON file in Application Support. About a year of days per person is too much for
/// UserDefaults, which loads whole at launch.
final class FileContributionHistoryPersistence: ContributionHistoryPersistence, @unchecked Sendable {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    /// `Application Support/<bundle id>/contribution-history.json`.
    static func live() -> FileContributionHistoryPersistence? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Committed", isDirectory: true)
        return FileContributionHistoryPersistence(url: folder.appendingPathComponent("contribution-history.json"))
    }

    func load() -> [String: ContributionHistory] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: ContributionHistory].self, from: data)) ?? [:]
    }

    func save(_ histories: [String: ContributionHistory]) {
        guard let data = try? JSONEncoder().encode(histories) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

final class InMemoryContributionHistoryPersistence: ContributionHistoryPersistence, @unchecked Sendable {
    private var storage: [String: ContributionHistory] = [:]
    func load() -> [String: ContributionHistory] { storage }
    func save(_ histories: [String: ContributionHistory]) { storage = histories }
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
