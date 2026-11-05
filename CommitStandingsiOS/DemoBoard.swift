#if DEBUG
import Foundation

/// A signed-in board with canned people and counts, for simulator screenshots: launch with
/// `-demoBoard`. Real Connect GitHub needs a person to approve at github.com, so screenshots of
/// the board can't come from the live flow. Everything is in memory; the real snapshot and
/// Keychain are untouched. DEBUG builds only.
extension AppDependencies {
    static func demo() -> AppDependencies {
        var dependencies = AppDependencies(
            credentials: InMemoryGitHubCredentialStore(token: "demo"),
            gitHubSession: URLSession(configuration: .ephemeral),
            contributions: DemoContributions(),
            competitorPersistence: InMemoryCompetitorPersistence(),
            snapshotPersistence: InMemoryStandingsSnapshotPersistence(),
            hiddenPeoplePersistence: InMemoryHiddenPeoplePersistence(),
            rosterPersistence: nil
        )
        // A second refresh a few seconds after launch moves you up one place today.
        dependencies.refreshInterval = 4
        dependencies.rosterFetch = { _, _ in
            GitHubRosterSnapshot(
                owner: "octocat",
                sources: [
                    GitHubRosterSource(id: "org:github", title: "github", members: ["defunkt", "mojombo", "pjhyett"]),
                    GitHubRosterSource(id: "following", title: "People you follow",
                                       members: ["gaearon", "sindresorhus", "torvalds"]),
                ],
                updatedAt: Date()
            )
        }
        return dependencies
    }
}

private actor DemoContributions: ContributionsFetching {
    private var fetchesOfYou = 0

    func standingCounts(
        for username: String,
        window: ContributionWindow,
        asOf reference: Date
    ) async -> Result<StandingCounts, ContributionsError> {
        try? await Task.sleep(for: .milliseconds(300))
        if username == "pjhyett" { return .failure(.network("The request timed out.")) }
        var daily = ["torvalds": 12, "gaearon": 9, "octocat": 7, "sindresorhus": 7, "defunkt": 3, "mojombo": 0][username] ?? 0
        if username == "octocat", window == .daily {
            fetchesOfYou += 1
            if fetchesOfYou > 1 { daily = 10 }
        }
        let multiplier = window == .daily ? 1 : (window == .weekly ? 6 : 23)
        return .success(StandingCounts(contributions: daily * multiplier + (window == .daily ? 0 : username.count)))
    }
}
#endif
