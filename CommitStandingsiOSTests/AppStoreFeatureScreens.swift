import Foundation
import SwiftUI
import Testing
import UIKit
@testable import CommitStandingsiOS

// The screens 1.1 added, for the screenshot editor: the Board with Your rivals and the record card,
// someone's person view (your race, the weekly record, their streak and month), your own view, their
// Challenge story, Share board and People. Each is the real app in the same 440 × 956 pt window as
// `AppStoreScreenshots`, at 3x, with its status bar: renders, not runtime captures.
//
// Two boards feed them:
// - The Sample board, always (`AppStoreFeatureScreenTests`): the made-up people, with a record set
//   today and two rivals pinned. Nothing is fetched.
// - The owner's real board, only when asked (`RealBoardTests`): a `BoardSnapshot` of public
//   contribution calendars, read from a roster file the owner keeps outside the repo. See
//   docs/screenshots/app-store/README.md, "Your real board".

/// One bare screen: 1320 × 2868 px, or 1080 × 1920 for the Challenge story.
struct AppStoreScreen {
    let name: String
    let png: Data
    /// Every GitHub login it shows.
    let people: Set<String>
}

@MainActor
extension AppStoreScreenshots {
    /// The newer screens on a loaded `model`, with `rival` as the person view's and the Challenge's
    /// friend. `now` is the model's clock, for Share board's age.
    static func featureScreens(model: AppModel, rival: String, now: Date,
                               settle: Duration = .seconds(2)) async throws -> [AppStoreScreen] {
        let window = try AppScreenWindow(model: model)
        defer { window.close() }
        let owner = try #require(model.store.selfCompetitor?.username, "the board has no you")

        // The private-contributions tip is a one-time hint; it would sit half under the tab bar.
        let tipKey = "dismissedPrivateContribTip"
        let tipWasDismissed = UserDefaults.standard.object(forKey: tipKey)
        UserDefaults.standard.set(true, forKey: tipKey)
        defer { UserDefaults.standard.set(tipWasDismissed, forKey: tipKey) }

        var screens: [AppStoreScreen] = []
        func add(_ name: String, _ image: UIImage, _ people: Set<String>) throws {
            screens.append(AppStoreScreen(name: name, png: try opaquePNG(
                AppScreen(image: image)
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, .dark)
            ), people: people))
        }

        model.selectedTab = .board
        model.selectedPerson = nil
        try add("board", try await window.capture(settle: settle), Set(model.store.visibleCompetitors.map(\.username)))

        model.showPerson(rival)
        try add("person", try await window.capture(settle: settle), [owner, rival])
        if let person = model.shownPerson, let challenge = model.challenge(for: person),
           let story = ChallengeShareRenderer.image(challenge, savedAvatars: .shared) {
            let points = CGSize(width: story.size.width * story.scale / 3, height: story.size.height * story.scale / 3)
            screens.append(AppStoreScreen(name: "challenge", png: try opaquePNG(
                Image(uiImage: story).resizable().frame(width: points.width, height: points.height)
            ), people: [owner, rival]))
        }

        model.showPerson(owner)
        try add("you", try await window.capture(settle: settle), [owner])
        model.selectedPerson = nil

        if let shared = WidgetSnapshot.board(
            model.store, window: model.store.selectedWindow,
            rankDelta: { model.refresh.rankDelta(for: $0) }, now: now,
            rows: BoardShareFormat.maxBoardRows
        ) {
            let image = try await window.capture(presenting: BoardShareSheet(snapshot: shared, initialFormat: .story))
            try add("share", image, Set([shared.selfLogin] + shared.top.map(\.login)))
        }

        model.selectedTab = .people
        try add("people", try await window.capture(settle: settle), Set(model.store.competitors.map(\.username)))
        model.selectedTab = .board
        return screens
    }

    /// The Sample board for the newer screens: Ari Linden sets a best day today (the record card),
    /// with Ezra Q and Odile M pinned as rivals.
    static func sampleFeatureModel() async -> AppModel {
        let model = AppModel(services: SampleServices.make(SampleServices.Options(recordDay: 64)),
                             backgroundTime: StillBackgroundTime())
        await model.sceneDidBecomeActive()
        await model.pullToRefresh()
        for login in ["ezra-q", "odile-m"] { model.store.setPinned(true, username: login) }
        await model.visibilityDidChange()
        return model
    }

    /// The owner's real board from a snapshot: its people, hidden people and rivals, with real
    /// avatars saved first so the screens show faces, and the clock at the snapshot's time.
    /// `activities` and `widgets` record what Live rank and the widgets would show.
    static func snapshotModel(_ snapshot: BoardSnapshot,
                              activities: any LiveRankActivities = NoLiveRankActivities(),
                              widgets: WidgetPublisher = WidgetPublisher(save: { _ in }, reload: {})) async -> AppModel {
        let now = snapshot.fetchedAt
        await GitHubAvatarPrefetcher.live().prefetch(snapshot.everyone)
        let model = AppModel(services: SnapshotServices.make(snapshot, now: { now }),
                             backgroundTime: StillBackgroundTime(), liveRankActivities: activities,
                             widgets: widgets, now: { now })
        await model.sceneDidBecomeActive()
        for login in snapshot.hidden { model.store.setHidden(true, username: login) }
        for login in snapshot.pins { model.store.setPinned(true, username: login) }
        await model.visibilityDidChange()
        await model.pullToRefresh()
        return model
    }

    /// Writes each screen to `directory` as `<prefix><name>.png`.
    static func write(_ screens: [AppStoreScreen], to directory: URL, prefix: String = "") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for screen in screens {
            try screen.png.write(to: directory.appendingPathComponent("\(prefix)\(screen.name).png"), options: .atomic)
        }
    }
}

@MainActor
@Suite(.serialized)
struct AppStoreFeatureScreenTests {
    private static let samplePeople: Set<String> = ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"]

    @Test func theNewerScreensFromTheSampleBoard() async throws {
        GitHubTrafficRecorder.start()
        defer { GitHubTrafficRecorder.stop() }

        let model = await AppStoreScreenshots.sampleFeatureModel()
        let screens = try await AppStoreScreenshots.featureScreens(model: model, rival: "ezra-q", now: .now)

        #expect(screens.map(\.name) == ["board", "person", "challenge", "you", "share", "people"])
        for screen in screens {
            let image = try #require(UIImage(data: screen.png)?.cgImage, "\(screen.name) isn't a PNG")
            let expected = screen.name == "challenge" ? (1080, 1920) : (1320, 2868)
            #expect(image.width == expected.0 && image.height == expected.1, "\(screen.name) is \(image.width) × \(image.height)")
            #expect([.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), "\(screen.name) has an alpha channel")
            #expect(screen.people.isSubset(of: Self.samplePeople), "\(screen.name) shows \(screen.people.subtracting(Self.samplePeople))")
        }
        #expect(GitHubTrafficRecorder.unexpectedRequests.isEmpty)

        if let directory = ProcessInfo.processInfo.environment["RENDER_DIR"].map(URL.init(fileURLWithPath:)) {
            try AppStoreScreenshots.write(screens, to: directory.appendingPathComponent("screens"), prefix: "feature-")
        }
    }
}

/// The owner's real board, only when asked: `TEST_RUNNER_REAL_BOARD_FILE=<snapshot.json>` renders
/// its screens (the newer ones, the widgets, the share image and the Lock Screen) into `RENDER_DIR/real/`, and `TEST_RUNNER_REAL_BOARD_ROSTER=<roster.json>` first
/// (re)reads everyone's public calendar into that snapshot. Both files live outside the repo.
@MainActor
@Suite(.serialized)
struct RealBoardTests {
    private nonisolated static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["REAL_BOARD_FILE"] != nil, "Set TEST_RUNNER_REAL_BOARD_FILE to render your real board"))
    func rendersTheOwnersRealBoard() async throws {
        let file = URL(fileURLWithPath: try #require(Self.environment["REAL_BOARD_FILE"]))
        if let roster = Self.environment["REAL_BOARD_ROSTER"] {
            let snapshot = await (try BoardRoster.load(from: URL(fileURLWithPath: roster))).snapshot()
            try snapshot.write(to: file)
        }
        let snapshot = try BoardSnapshot.load(from: file)
        #expect(snapshot.history(for: snapshot.owner) != nil, "\(snapshot.owner)'s calendar wasn't read")
        // Organizations you follow have no calendar; the board shows anyone unread as not loaded.
        let unread = snapshot.everyone.filter { snapshot.calendars[$0] == nil }
        if !unread.isEmpty { print("RealBoardTests: no calendar for \(unread.joined(separator: ", "))") }

        guard let directory = Self.environment["RENDER_DIR"].map(URL.init(fileURLWithPath:)) else { return }
        let activities = FakeLiveRankActivities()
        let widgets = RecordingWidgets()
        let model = await AppStoreScreenshots.snapshotModel(snapshot, activities: activities, widgets: widgets.publisher)
        let rival = snapshot.pins.first ?? Self.closestRival(in: snapshot)
        var screens = try await AppStoreScreenshots.featureScreens(
            model: model, rival: try #require(rival, "nobody to race"), now: snapshot.fetchedAt, settle: .seconds(3)
        )
        let surfaces = SampleBoardSurfaces(
            snapshot: try #require(widgets.last, "the widgets got nothing"),
            liveRank: try #require(activities.running.first?.state, "Live rank didn't start"),
            selfLogin: snapshot.owner
        )
        screens.append(AppStoreScreen(name: "widgets", png: try AppStoreScreenshots.opaquePNG(
            HomeScreen(snapshot: surfaces.snapshot).environment(\.colorScheme, .dark)
        ), people: Set([surfaces.snapshot.selfLogin] + surfaces.snapshot.top.map(\.login))))
        screens += try AppStoreScreenshots.listingScreens(model: model, surfaces: surfaces, now: snapshot.fetchedAt)
        let banners = AppStoreScreenshots.notifications(for: surfaces.liveRank)
        print("RealBoardTests: Lock Screen notifications: \(banners.map(\.title))")
        try AppStoreScreenshots.write(screens, to: directory.appendingPathComponent("real"))
    }

    /// Whoever's 30 days are closest to yours, among the people shown: the tightest race.
    private static func closestRival(in snapshot: BoardSnapshot) -> String? {
        func total(_ login: String) -> Int? { snapshot.history(for: login)?.total(for: .monthly, asOf: snapshot.fetchedAt) }
        guard let yours = total(snapshot.owner) else { return nil }
        return snapshot.people
            .filter { !snapshot.hidden.contains($0) }
            .compactMap { login in total(login).map { (login, abs($0 - yours)) } }
            .min { $0.1 < $1.1 }?.0
    }
}
