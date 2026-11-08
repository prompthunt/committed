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

    private func makeModel(signedIn: Bool = true, counts: [String: Int] = ["me": 3, "ada": 5, "bo": 1])
        -> (AppModel, FakeContributions) {
        let contributions = FakeContributions(counts)
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
            liveRankActivities: activities, widgets: widgets.publisher
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
        #expect(snapshot.selfRow == .init(rank: 9, login: "you", contributions: 12, movement: 1, isSelf: true))
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
}
