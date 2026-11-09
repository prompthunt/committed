import Foundation
import Testing
@testable import CommitStandingsiOS

/// The Sample board through the app model: try it from Connect GitHub, come back to it after a
/// relaunch, leave it, or replace it with a real board. Nothing on it leaves the device.
@MainActor
@Suite(.serialized)
struct SampleBoardTests {
    let clock = TestClock()
    let rosterCalls = RosterCalls()
    let activities = FakeLiveRankActivities()
    let relay = FakeLiveRankRelay()
    /// The real board's saved Live rank settings, shared across "launches".
    let preferences = InMemoryLiveRankPreferences()
    let widgets = RecordingWidgets()
    /// This test's own UserDefaults, standing in for `.standard` across "launches".
    let defaults: UserDefaults
    let realContributions = FakeContributions(["me": 3, "ada": 5])
    let backgroundTime = FakeBackgroundTime()
    /// Where the real board's avatars are saved for Live rank and the widgets (the App Group's
    /// `AvatarCache` in the app).
    let avatarCache = AvatarCache(directory: FileManager.default.temporaryDirectory
        .appending(path: "SampleBoardTests-\(UUID().uuidString)", directoryHint: .isDirectory))

    init() {
        defaults = UserDefaults(suiteName: "SampleBoardTests-\(UUID().uuidString)")!
        // A relay is configured for the real board, so the Sample board has to avoid it on purpose.
        relay.pushUpdates = .token
    }

    /// One launch of the app: a real, not-yet-connected graph (Keychain-like token in memory) whose
    /// hidden people persist in `defaults`, like the shipping app's.
    /// `gate` holds each device-flow poll until it opens (or the connect is cancelled), so a test
    /// can act while Connect GitHub is in flight with its code showing.
    private func launch(
        token: String? = nil,
        gitHub: URLProtocol.Type = ApprovingGitHubProtocol.self,
        gate: PollGate? = nil
    ) -> AppModel {
        let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [gitHub]
            return URLSession(configuration: config)
        }()
        let clock = clock
        let rosterCalls = rosterCalls
        let services = CommittedServices(
            store: StandingsStore(
                persistence: InMemoryCompetitorPersistence(),
                hiddenPeoplePersistence: UserDefaultsHiddenPeoplePersistence(defaults: defaults)
            ),
            credentials: InMemoryGitHubCredentialStore(token: token),
            contributions: realContributions,
            gitHubAuth: GitHubAuth(clientID: "test", session: session,
                                   sleep: { _ in await gate?.wait() }, now: { clock.now }),
            accountFactory: { GitHubAccountClient(token: $0, session: session) },
            fetchRoster: { _ in
                rosterCalls.count += 1
                return GitHubRosterSnapshot(owner: "me", sources: [
                    GitHubRosterSource(id: "following", title: "Following", members: ["ada"]),
                ], updatedAt: clock.now)
            },
            refreshInterval: 9_999,
            now: { clock.now }
        )
        return AppModel(
            services: services,
            sampleServices: { [clock] in SampleServices.make(now: { clock.now }) },
            defaults: defaults,
            backgroundTime: backgroundTime,
            liveRankActivities: activities,
            liveRankPreferences: preferences,
            liveRankRelay: relay,
            widgets: widgets.publisher,
            avatarCache: avatarCache,
            now: { [clock] in clock.now }
        )
    }

    private let sampleBoard = ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"]

    /// Waits (up to 5 s) for something an in-flight task will do.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    private func board(_ model: AppModel, _ window: ContributionWindow = .daily) -> [String] {
        Ranking.order(competitors: model.store.visibleCompetitors,
                      standings: model.store.standings(for: window), window: window)
            .map(\.competitor.username)
    }

    // MARK: Starting

    @Test func startingTheSampleBoardPublishesARankedBoard() async throws {
        let model = launch()
        #expect(model.mode == .notConnected)
        #expect(model.needsConnect)

        await model.startSampleBoard()

        #expect(model.mode == .sampleBoard)
        #expect(!model.needsConnect)
        #expect(board(model) == ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"])
        let snapshot = try #require(widgets.last)
        #expect(snapshot.selfLogin == "ari-linden")
        #expect(snapshot.top.map(\.login) == ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"])
    }

    @Test func theSampleBoardSurvivesARelaunch() async {
        await launch().startSampleBoard()

        let relaunched = launch()
        #expect(relaunched.mode == .sampleBoard)
        #expect(!relaunched.needsConnect)
        await relaunched.sceneDidBecomeActive()
        #expect(board(relaunched) == ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"])
    }

    // MARK: Leaving

    @Test func leavingReturnsToConnectGitHub() async {
        let model = launch()
        await model.startSampleBoard()
        #expect(!activities.running.isEmpty) // Live rank on the phone

        await model.leaveSampleBoard()

        #expect(model.mode == .notConnected)
        #expect(model.needsConnect)
        #expect(model.store.competitors.isEmpty)
        #expect(activities.running.isEmpty)
        #expect(widgets.published.last == .some(nil))
        #expect(launch().mode == .notConnected)
    }

    // MARK: Connecting

    @Test func connectingFromTheSampleBoardLeavesNoSampleState() async {
        let model = launch()
        await model.startSampleBoard()
        model.store.setHidden(true, username: "bram-ott")
        await model.visibilityDidChange()

        await model.connectGitHub()

        #expect(model.mode == .connected)
        #expect(Set(model.store.competitors.map(\.username)) == ["me", "ada"])
        #expect(board(model) == ["ada", "me"])
        // The hide on the Sample board never reached the saved visibility preferences.
        #expect(UserDefaultsHiddenPeoplePersistence(defaults: defaults).load().isEmpty)
        #expect(widgets.last?.selfLogin == "me")
        #expect(launch(token: "gho_new").mode == .connected)
    }

    @Test func theCodeShowsOverTheSampleBoardAndCancelReturnsToIt() async throws {
        let gate = PollGate()
        defer { gate.open() }
        let model = launch(gate: gate)
        await model.startSampleBoard()
        model.store.setHidden(true, username: "bram-ott")
        model.selectedTab = .people

        let connecting = Task { await model.connectGitHub() }
        try await waitUntil { model.connectAuth.phase != .signedOut }

        // GitHub's code shows over the Sample board, which stays up underneath.
        #expect(model.connectAuth.phase == .connecting(userCode: "ABCD-1234", verificationURL: "https://github.com/login/device"))
        #expect(model.isConnectingFromSampleBoard)
        #expect(model.isShowingConnectOverSampleBoard)
        #expect(model.mode == .sampleBoard)
        #expect(!model.needsConnect)
        #expect(board(model) == ["ines-volk", "odile-m", "ezra-q", "ari-linden"])

        model.closeConnectOverSampleBoard() // Cancel
        await connecting.value

        #expect(!model.isConnectingFromSampleBoard)
        #expect(!model.isShowingConnectOverSampleBoard)
        #expect(model.mode == .sampleBoard)
        #expect(model.selectedTab == .people)
        #expect(board(model) == ["ines-volk", "odile-m", "ezra-q", "ari-linden"])
        // Cancelling isn't an error.
        #expect(model.connectAuth.errorMessage == nil)
        #expect(model.sampleBoardConnectError == nil)
        #expect(activities.running.map(\.selfLogin) == ["ari-linden"])
        #expect(widgets.last?.selfLogin == "ari-linden")
        #expect(launch().mode == .sampleBoard)
    }

    @Test func aDeclinedConnectFromTheSampleBoardStaysOnTheSampleBoard() async {
        let model = launch(gitHub: DecliningGitHubProtocol.self)
        await model.startSampleBoard()
        model.selectedTab = .settings

        await model.connectGitHub()

        #expect(model.mode == .sampleBoard)
        #expect(!model.needsConnect)
        #expect(!model.isConnectingFromSampleBoard)
        #expect(model.sampleBoardConnectError == "The GitHub connection was declined.")
        // The reason shows over the Sample board, with Try Again; Cancel uncovers it.
        #expect(model.isShowingConnectOverSampleBoard)
        model.closeConnectOverSampleBoard()
        #expect(!model.isShowingConnectOverSampleBoard)
        #expect(model.sampleBoardConnectError == nil)
        #expect(model.selectedTab == .settings)
        #expect(board(model) == sampleBoard)
        #expect(activities.running.map(\.selfLogin) == ["ari-linden"])
        #expect(widgets.last?.selfLogin == "ari-linden")
        #expect(launch().mode == .sampleBoard)
    }

    @Test func theSampleBoardCantStartOrEndWhileConnectGitHubIsInFlight() async throws {
        let gate = PollGate()
        defer { gate.open() }
        let model = launch(gate: gate)

        let connecting = Task { await model.connectGitHub() }
        try await waitUntil { model.connectAuth.phase != .signedOut }

        // A tap on Try a sample board, or a second Connect GitHub, while the code shows.
        await model.startSampleBoard()
        #expect(model.mode == .notConnected)
        await model.connectGitHub()

        gate.open()
        await connecting.value

        // Connected on the real account, with one device flow.
        #expect(model.mode == .connected)
        #expect(board(model) == ["ada", "me"])
        #expect(backgroundTime.log == ["begin Connect GitHub", "end 1"])
        #expect(launch(token: "gho_new").mode == .connected)
    }

    @Test func leavingIsIgnoredWhileConnectingFromTheSampleBoard() async throws {
        let gate = PollGate()
        defer { gate.open() }
        let model = launch(gate: gate)
        await model.startSampleBoard()

        let connecting = Task { await model.connectGitHub() }
        try await waitUntil { model.connectAuth.phase != .signedOut }
        await model.leaveSampleBoard()
        #expect(model.mode == .sampleBoard)

        gate.open()
        await connecting.value

        #expect(model.mode == .connected)
        #expect(board(model) == ["ada", "me"])
    }

    // MARK: Avatars

    @Test func theSampleBoardNeverShowsSavedAvatars() async throws {
        let model = launch()
        #expect(model.savedAvatars?.directory == avatarCache.directory)

        await model.startSampleBoard()

        // Initials only: the app, Live rank and the widgets never read the saved avatars, which
        // may hold a real person's face for a sample login.
        #expect(model.savedAvatars == nil)
        #expect(widgets.last?.isSampleBoard == true)
        #expect(activities.startedAttributes.map(\.isSampleBoard) == [true])
        // Share board's image too.
        let shared = try #require(model.boardToShare())
        #expect(shared.isSampleBoard == true)
        #expect(shared.savedAvatars == nil)

        await model.connectGitHub()

        #expect(model.savedAvatars?.directory == avatarCache.directory)
        #expect(widgets.last?.selfLogin == "me")
        #expect(widgets.last?.isSampleBoard == nil)
        #expect(try #require(model.boardToShare()).isSampleBoard == nil)
    }

    // MARK: Live rank and the widgets (#68)

    private var registered: [LiveRankConfiguration] { relay.configurations.compactMap { $0 } }

    @Test func liveRankStartsOnThePhoneOnlyEvenWithARelayConfigured() async throws {
        let model = launch()

        await model.startSampleBoard()

        #expect(activities.running.map(\.selfLogin) == ["ari-linden"])
        let state = try #require(activities.states.first)
        #expect(state.rank == 4)
        #expect(state.above?.login == "ezra-q")
        #expect(model.liveRank.status == .live)
        #expect(model.liveRank.isEnabled)
        #expect(!model.liveRank.isRelayConfigured)
        #expect(activities.startedPushUpdates == [.none])
        #expect(registered.isEmpty)
        #expect(relay.retries == 0)
        #expect(!model.isShowingLiveRankDisclosure)
    }

    @Test func theLiveRankSwitchOnTheSampleBoardNeverAsksForTheRelayDisclosure() async {
        let model = launch()
        await model.startSampleBoard()

        await model.liveRankSwitchChanged(false)
        #expect(activities.running.isEmpty)
        #expect(model.liveRank.status == .off)

        await model.liveRankSwitchChanged(true)
        #expect(!model.isShowingLiveRankDisclosure)
        #expect(activities.running.map(\.selfLogin) == ["ari-linden"])
        #expect(activities.startedPushUpdates == [.none, .none])

        await model.setLiveRankWindow(.weekly)
        #expect(activities.states.map(\.window) == ["weekly"])
        #expect(widgets.last?.state.window == "weekly")

        #expect(registered.isEmpty)
        // The Sample board's switch and Window are its own: the real board's settings are untouched.
        #expect(preferences.load() == LiveRankPreferences())
    }

    @Test func theWidgetsShowTheSampleBoard() async throws {
        let model = launch()
        await model.startSampleBoard()

        // What the widget extension reads back from the App Group.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try #require(widgets.last).save(to: file)
        let snapshot = try #require(WidgetSnapshot.load(from: file))

        #expect(snapshot.selfLogin == "ari-linden")
        #expect(snapshot.state.window == "daily")
        #expect(snapshot.state.competitorCount == 5)
        #expect(snapshot.top.map(\.login) == ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"])
        // Home Screen: small and medium read the state; large reads the rows.
        #expect(snapshot.state.rank == 4)
        #expect(snapshot.state.contributions == 5)
        #expect(snapshot.state.passLine == "1 to pass ezra-q")
        // Lock Screen accessories.
        #expect(CommittedWidgetText.headline(snapshot.state) == "#4 · 5 today")
        #expect(CommittedWidgetText.inline(snapshot.state) == "#4 · 1 to pass ezra-q")
        // The Committed Board widget.
        #expect(snapshot.boardRows().map(\.login) == ["ines-volk", "odile-m", "ezra-q", "ari-linden"])

        // Pull to refresh: Ari passes Ezra, and the widgets follow.
        await model.pullToRefresh()
        let moved = try #require(widgets.last)
        #expect(moved.state.rank == 3)
        #expect(moved.state.movementToday == 1)
        #expect(moved.state.passLine == "2 to pass odile-m")
        #expect(moved.boardRows().map(\.login) == ["ines-volk", "odile-m", "ari-linden", "ezra-q"])
        #expect(moved.boardRows().map(\.movement) == [0, 0, 1, -1])
    }

    @Test func leavingEndsLiveRankAndResetsTheWidgets() async throws {
        let model = launch()
        await model.startSampleBoard()
        let started = try #require(activities.running.first?.id)
        #expect(widgets.last?.selfLogin == "ari-linden")

        await model.leaveSampleBoard()

        #expect(activities.running.isEmpty)
        #expect(activities.log.contains("end \(started)"))
        #expect(model.liveRank.status != .live)
        // nil is what turns every widget into "Connect GitHub".
        #expect(widgets.published.last == .some(nil))
        #expect(registered.isEmpty)
    }

    @Test func connectingFromTheSampleBoardRegistersWithTheRelayAfterTheDisclosure() async {
        let model = launch()
        await model.startSampleBoard()

        await model.connectGitHub()

        // As a normal Connect GitHub: the board loads, and Live rank waits for the disclosure.
        #expect(model.mode == .connected)
        #expect(model.isShowingLiveRankDisclosure)
        #expect(model.liveRank.isRelayConfigured)
        #expect(activities.running.isEmpty)
        #expect(registered.isEmpty)
        #expect(widgets.last?.selfLogin == "me")

        await model.acceptLiveRankDisclosure()

        #expect(!model.isShowingLiveRankDisclosure)
        #expect(registered == [LiveRankConfiguration(selfLogin: "me", competitors: ["me", "ada"], window: .daily)])
        #expect(activities.running.map(\.selfLogin) == ["me"])
        #expect(activities.startedPushUpdates == [.none, .token])
        #expect(activities.startedAttributes.map(\.isSampleBoard) == [true, nil])
        #expect(preferences.load() == LiveRankPreferences(isEnabled: true, window: .daily, relayDisclosureAccepted: true))
    }

    @Test func turningLiveRankOffOnTheSampleBoardStillOffersTheDisclosureAfterConnecting() async {
        let model = launch()
        await model.startSampleBoard()
        await model.liveRankSwitchChanged(false)

        await model.connectGitHub()

        #expect(model.mode == .connected)
        #expect(model.isShowingLiveRankDisclosure)
        #expect(registered.isEmpty)
    }

    // MARK: Nothing leaves the device

    @Test func nothingLeavesTheDeviceOnTheSampleBoard() async throws {
        let control = try #require(URL(string: "https://api.github.com/recorder-check/\(UUID().uuidString)"))
        GitHubTrafficRecorder.start()
        defer { GitHubTrafficRecorder.stop() }
        _ = try? await URLSession.shared.data(from: control)
        #expect(GitHubTrafficRecorder.requests.contains(control))

        let model = launch()
        await model.startSampleBoard()
        await model.pullToRefresh()
        model.store.selectedWindow = .weekly
        await model.windowDidChange()
        model.store.setHidden(true, username: "ezra-q")
        await model.visibilityDidChange()
        await model.setLiveRankWindow(.monthly)
        model.sceneDidEnterBackground()
        await model.backgroundRefresh()
        await model.sceneDidBecomeActive()

        #expect(model.mode == .sampleBoard)
        #expect(board(model) == ["ines-volk", "odile-m", "ari-linden", "bram-ott"])
        #expect(await realContributions.total() == 0)
        #expect(rosterCalls.count == 0)
        // Live rank runs on the phone only: never registered with the relay, no push token asked.
        #expect(relay.configurations.compactMap { $0 }.isEmpty)
        #expect(!activities.startedPushUpdates.isEmpty)
        #expect(activities.startedPushUpdates.allSatisfy { $0 == .none })
        #expect(!model.isShowingLiveRankDisclosure)
        #expect(GitHubTrafficRecorder.unexpectedRequests.isEmpty)
    }
}

/// Shows a device code, then GitHub reports the person declined.
private final class DecliningGitHubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.url?.path == "/login/device/code"
            ? #"{"device_code":"d","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#
            : #"{"error":"access_denied"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Holds each device-flow poll until opened. A cancelled connect gets through too, as it does
/// through the real `Task.sleep`.
final class PollGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false

    func open() { lock.withLock { isOpen = true } }

    func wait() async {
        while !lock.withLock({ isOpen }) && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
