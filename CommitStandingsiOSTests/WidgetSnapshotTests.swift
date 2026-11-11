import Foundation
import Testing
@testable import CommitStandingsiOS

/// Records what the app would write to the App Group and how often it reloads the widgets.
@MainActor
final class RecordingWidgets {
    private(set) var published: [WidgetSnapshot?] = []
    private(set) var reloads = 0

    lazy var publisher = WidgetPublisher(
        save: { [unowned self] in published.append($0) },
        reload: { [unowned self] in reloads += 1 }
    )

    var last: WidgetSnapshot? { published.last ?? nil }
}

@MainActor
struct WidgetSnapshotTests {
    let clock = TestClock()
    let activities = FakeLiveRankActivities()
    let widgets = RecordingWidgets()

    private func makeModel(signedIn: Bool = true, counts: [String: Int] = ["me": 3, "ada": 5, "bo": 1],
                           histories: [String: ContributionHistory] = [:])
        -> (AppModel, FakeContributions) {
        let contributions = FakeContributions(counts, histories: histories)
        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [ApprovingGitHubProtocol.self]
            return URLSession(configuration: config)
        }()
        let clock = clock
        let services = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: signedIn ? "gho_test" : nil),
            contributions: contributions,
            gitHubAuth: GitHubAuth(clientID: "test", session: session, sleep: { _ in }, now: { clock.now }),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                GitHubRosterSnapshot(owner: "me", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["ada", "bo"]),
                ], updatedAt: clock.now)
            },
            refreshInterval: 9_999,
            now: { clock.now }
        )
        let model = AppModel(
            services: services, backgroundTime: FakeBackgroundTime(),
            liveRankActivities: activities, widgets: widgets.publisher,
            // The same clock as the services', so streaks are worked out on the test's day.
            now: { clock.now }
        )
        return (model, contributions)
    }

    // MARK: Publishing

    @Test func aRefreshPublishesTheBoardInRankOrder() async throws {
        let (model, _) = makeModel()

        await model.sceneDidBecomeActive()

        let snapshot = try #require(widgets.last)
        #expect(snapshot.selfLogin == "me")
        #expect(snapshot.top.map(\.login) == ["ada", "me", "bo"])
        #expect(snapshot.top.map(\.rank) == [1, 2, 3])
        #expect(snapshot.top.map(\.contributions) == [5, 3, 1])
        #expect(snapshot.top.map(\.isSelf) == [false, true, false])
        #expect(snapshot.state.rank == 2)
        #expect(snapshot.state.passLine == "2 to pass ada")
        #expect(snapshot.selfIsInTop)
    }

    /// Streaks from each person's calendar, on the rows and in Live rank's state (yours and your
    /// neighbors'), so the widgets show them and their own refresh can carry them on.
    @Test func aRefreshPublishesStreaksOnRowsAndInState() async throws {
        let utc = TimeZone(identifier: "UTC")! // the clock reads 2033-05-18 03:33 UTC
        let (model, _) = makeModel(histories: [
            "me": ContributionHistory(days: ["2033-05-16": 0, "2033-05-17": 2, "2033-05-18": 1], timeZone: utc),
            "ada": ContributionHistory(days: ["2033-05-14": 1, "2033-05-15": 1, "2033-05-16": 1, "2033-05-17": 1, "2033-05-18": 5], timeZone: utc),
            "bo": ContributionHistory(days: ["2033-05-17": 0, "2033-05-18": 0], timeZone: utc),
        ])

        await model.sceneDidBecomeActive()

        let snapshot = try #require(widgets.last)
        #expect(snapshot.top.map(\.login) == ["ada", "me", "bo"])
        #expect(snapshot.top.map(\.streak) == [5, 2, 0])
        #expect(snapshot.board?.map(\.streak) == [5, 2, 0])
        #expect(snapshot.state.streak == 2)
        #expect(snapshot.state.above?.streak == 5)
        #expect(snapshot.state.below?.streak == 0)
        #expect(snapshot.selfRow?.streak == 2)
    }

    @Test func notConnectedPublishesNothing() async {
        let (model, _) = makeModel(signedIn: false)

        await model.sceneDidBecomeActive()

        #expect(widgets.published.allSatisfy { $0 == nil })
        #expect(!widgets.published.isEmpty)
    }

    @Test func disconnectClearsTheWidgets() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        #expect(widgets.last != nil)

        model.auth.signOut()

        #expect(widgets.published.last == .some(nil))
    }

    /// Reloads come out of WidgetKit's daily budget: the same board never reloads twice.
    @Test func anUnchangedBoardDoesNotReloadAgain() async {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()
        let reloads = widgets.reloads

        model.publishWidgets()
        await model.visibilityDidChange()

        #expect(widgets.reloads == reloads)
    }

    @Test func hidingSomeoneUpdatesTheWidgetsRightAway() async throws {
        let (model, _) = makeModel()
        await model.sceneDidBecomeActive()

        model.store.setHidden(true, username: "ada")
        await model.visibilityDidChange()

        let snapshot = try #require(widgets.last)
        #expect(snapshot.top.map(\.login) == ["me", "bo"])
        #expect(snapshot.state.rank == 1)
    }

    /// The widgets show Live rank's Window, and keep it fetched even when iOS won't show Live
    /// Activities.
    @Test func followsLiveRanksWindowEvenWithLiveActivitiesOff() async throws {
        activities.areActivitiesEnabled = false
        let (model, contributions) = makeModel()
        await model.sceneDidBecomeActive()

        await model.setLiveRankWindow(.weekly)

        #expect(await contributions.windows.contains(.weekly))
        let snapshot = try #require(widgets.last)
        #expect(snapshot.state.window == ContributionWindow.weekly.rawValue)
        #expect(snapshot.top.allSatisfy { $0.movement == 0 })
    }

    // MARK: Snapshot

    @Test func youJoinTheLargeWidgetBelowTheLeaders() {
        var snapshot = WidgetSnapshot.sample()
        snapshot.top = (1...6).map { .init(rank: $0, login: "p\($0)", contributions: 40 - $0, movement: 0, isSelf: false) }
        snapshot.state.rank = 9
        snapshot.state.contributions = 12

        #expect(!snapshot.selfIsInTop)
        snapshot.state.streak = 14
        #expect(snapshot.selfRow == .init(rank: 9, login: "ari-linden", contributions: 12, movement: 1, isSelf: true, streak: 14))
    }

    // MARK: Board list (StandBy)

    @Test func theBoardListShowsTheLeadersWhenYoureAmongThem() {
        let rows = WidgetSnapshot.sample().boardRows()
        #expect(rows.map(\.rank) == [1, 2, 3, 4])
        #expect(rows.filter(\.isSelf).map(\.rank) == [3])
    }

    @Test func furtherDownTheBoardListShowsYourRace() {
        var snapshot = WidgetSnapshot.sample()
        snapshot.top = (1...6).map { .init(rank: $0, login: "p\($0)", contributions: 40 - $0, movement: 0, isSelf: false) }
        snapshot.state.rank = 9
        snapshot.state.contributions = 12
        snapshot.state.above = .init(login: "taylor", contributions: 13, movementToday: 0, streak: 21)
        snapshot.state.streak = 6

        let rows = snapshot.boardRows()

        #expect(rows.map(\.login) == ["p1", "p2", "taylor", "ari-linden"])
        #expect(rows.map(\.rank) == [1, 2, 8, 9])
        // The rows rebuilt from Live rank's state keep their streaks.
        #expect(rows.suffix(2).map(\.streak) == [21, 6])
    }

    @Test func justBelowTheLeadersTheListDoesNotRepeatAnyone() {
        var snapshot = WidgetSnapshot.sample()
        snapshot.top = (1...6).map { .init(rank: $0, login: "p\($0)", contributions: 40 - $0, movement: 0, isSelf: $0 == 5) }
        snapshot.selfLogin = "p5"
        snapshot.state.rank = 5
        snapshot.state.contributions = 35
        snapshot.state.above = .init(login: "p4", contributions: 36, movementToday: 0)

        let rows = snapshot.boardRows()

        #expect(rows.map(\.rank) == [1, 2, 4, 5])
        #expect(Set(rows.map(\.login)).count == rows.count)
    }

    @Test func withoutYourCountTheListIsTheLeaders() {
        var snapshot = WidgetSnapshot.sample()
        snapshot.top = (1...6).map { .init(rank: $0, login: "p\($0)", contributions: 40 - $0, movement: 0, isSelf: false) }
        snapshot.state.rank = nil
        snapshot.state.contributions = nil

        #expect(snapshot.boardRows().map(\.rank) == [1, 2, 3, 4])
    }

    @Test func noRowForYouWithoutYourCount() {
        var snapshot = WidgetSnapshot.sample()
        snapshot.state.contributions = nil
        #expect(snapshot.selfRow == nil)
    }

    @Test func savesAndLoadsThroughAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString).json")
        defer { WidgetSnapshot.remove(at: url) }
        let snapshot = WidgetSnapshot.sample(now: Date(timeIntervalSince1970: 1_793_800_000))

        try snapshot.save(to: url)
        #expect(WidgetSnapshot.load(from: url) == snapshot)

        WidgetSnapshot.remove(at: url)
        #expect(WidgetSnapshot.load(from: url) == nil)
    }

    /// The placeholder is a whole board, so a fresh install never shows an empty box.
    @Test func theSampleIsAFullBoard() {
        let sample = WidgetSnapshot.sample()
        #expect(sample.top.count == WidgetSnapshot.topCount)
        #expect(sample.selfIsInTop)
        #expect(sample.state.passLine != nil)
    }

    /// The placeholder ships in the widget gallery, so it names only made-up GitHub logins: the
    /// Sample board's, each checked to not exist on GitHub on 2026-11-09 (see `SampleServicesTests`).
    @Test func theSampleNamesOnlyMadeUpGitHubLogins() {
        let sample = WidgetSnapshot.sample()
        let shown = Set([sample.selfLogin] + sample.top.map(\.login)
            + [sample.state.above?.login, sample.state.below?.login].compactMap { $0 })
        #expect(shown == ["ines-volk", "odile-m", "ari-linden", "ezra-q", "bram-ott", "niko-vane"])
    }
}
