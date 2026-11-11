import SwiftUI
import Testing
import UIKit
@testable import CommitStandingsiOS

/// The board's share images: every widget style in both shapes renders at the size feeds and
/// stories expect. With `RENDER_DIR` set (`TEST_RUNNER_RENDER_DIR=/path`), the images and the share
/// sheet are also saved there as PNGs, for review.
@MainActor
@Suite(.serialized)
struct BoardShareTests {
    private let renderDirectory = ProcessInfo.processInfo.environment["RENDER_DIR"].map(URL.init(fileURLWithPath:))

    @Test(arguments: BoardShareStyle.live, BoardShareFormat.allCases)
    func rendersAtThePostedSize(style: BoardShareStyle, format: BoardShareFormat) throws {
        let image = try #require(BoardShareRenderer.image(Self.board, style: style, format: format))
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        #expect(pixels == format.pixelSize)
        #expect(format.pixelSize == (format == .square ? CGSize(width: 1080, height: 1080) : CGSize(width: 1080, height: 1920)))
        if let renderDirectory {
            try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
            try #require(image.pngData()).write(to: renderDirectory.appendingPathComponent("share-\(style.rawValue)-\(format.rawValue).png"))
        }
    }

    @Test func fileIsAPNGNamedForWhatItShows() throws {
        let url = try BoardShareRenderer.file(Self.board, style: .board, format: .story)
        #expect(url.lastPathComponent == "Committed-Today-board-story.png")
        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func boardShowsMorePeopleThanTheWidget() {
        #expect(BoardShareFormat.square.boardRows == 8)
        #expect(BoardShareFormat.story.boardRows == 10)
        #expect(BoardShareFormat.maxBoardRows == 10)
        // You're sixth: the leaders, you among them.
        let square = Self.board.sharing(rows: 8)
        #expect(square.top.map(\.rank) == Array(1...8))
        #expect(square.selfIsInTop)
    }

    @Test func youStayOnTheImageWhenFurtherDown() {
        // You're 14th: seven leaders, then the large widget adds you below its rule.
        let square = Self.farDown.sharing(rows: 8)
        #expect(square.top.map(\.rank) == Array(1...7))
        #expect(!square.selfIsInTop)
        #expect(square.selfRow?.rank == 14)
    }

    @Test func timestampSaysWhenTheNumbersAreFrom() {
        let date = Date(timeIntervalSince1970: 1_794_172_920) // 2026-11-08 21:22 UTC
        let text = BoardShareCard.timestamp(date, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(text == "As of Nov 8, 2026 at 1:22\u{202F}PM" || text == "As of Nov 8, 2026, 1:22\u{202F}PM")
    }

    @Test func storyHeadlineFollowsTheWindow() {
        #expect(BoardShareCard.headline(.daily) == "Who shipped more today?")
        #expect(BoardShareCard.headline(.weekly) == "Who shipped more this week?")
        // 30 days is trailing, so only This month says "this month".
        #expect(BoardShareCard.headline(.monthly) == "Who shipped more in 30 days?")
        #expect(BoardShareCard.headline(.month) == "Who shipped more this month?")
    }

    /// The sheet as it opens from the Board, and the Board with its Share button, for the PR's
    /// screenshots.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil), arguments: BoardShareFormat.allCases)
    func sheet(format: BoardShareFormat) async throws {
        let window = try makeWindow(UIHostingController(rootView: BoardShareSheet(snapshot: Self.board, initialFormat: format)))
        try await save(window, name: "share-sheet-\(format.rawValue)")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil))
    func boardWithShareButton() async throws {
        let model = AppModel(services: ScreenshotFixture.services(), backgroundTime: ImmediateBackgroundTime())
        let root = RootView()
            .environment(model)
            .environment(model.store)
            .environment(model.refresh)
            .environment(model.auth)
            .environment(model.roster)
            .environment(model.services.notifications)
            .environment(\.loadsGitHubAvatars, false)
        let window = try makeWindow(UIHostingController(rootView: root))
        try await save(window, name: "share-board-button")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil), arguments: BoardShareFormat.allCases)
    func boardFarDown(format: BoardShareFormat) throws {
        let directory = try #require(renderDirectory)
        let image = try #require(BoardShareRenderer.image(Self.farDown, style: .board, format: format))
        try #require(image.pngData()).write(to: directory.appendingPathComponent("share-board-far-\(format.rawValue).png"))
    }

    /// This month's story as the app builds it from the Sample board on This month, for the PR's
    /// screenshots: "Who shipped more this month?".
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil))
    func thisMonthStoryFromTheSampleBoard() async throws {
        let directory = try #require(renderDirectory)
        let model = AppModel(services: SampleServices.make(), backgroundTime: ImmediateBackgroundTime())
        model.store.selectedWindow = .month
        await model.sceneDidBecomeActive()
        let snapshot = try #require(model.boardToShare())
        #expect(snapshot.state.window == "month")
        let image = try #require(BoardShareRenderer.image(snapshot, style: .board, format: .story))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(image.pngData()).write(to: directory.appendingPathComponent("share-board-this-month-story.png"))
    }

    // MARK: - Final standings

    /// The Sample board at noon on the `day`th of November 2026, after its first refresh.
    private func sampleBoard(onNovember day: Int) async throws -> AppModel {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12)))
        let model = AppModel(services: SampleServices.make(now: { date }), backgroundTime: ImmediateBackgroundTime())
        await model.sceneDidBecomeActive()
        return model
    }

    private static let october = CalendarMonth(year: 2026, month: 10)

    @Test func theBoardOffersLastMonthsFinalStandingsOnThe1st() async throws {
        let model = try await sampleBoard(onNovember: 1)
        let request = try #require(model.boardShareRequest())
        #expect(request.styles == [.final, .board, .race, .rank, .list])
        // The Board opens on the Final standings on the 1st, and so does its share.
        #expect(request.initialStyle == .final)
        let finals = try #require(request.finals)
        #expect(finals.month == Self.october)
        #expect(finals.title == "October final")
        // The large widget's rows, medals on the top three, no streaks or movement.
        #expect(finals.snapshot.top.map(\.medal) == [.gold, .silver, .bronze, nil, nil])
        #expect(finals.snapshot.top.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(finals.snapshot.top.allSatisfy { $0.streak == nil && $0.movement == 0 })
        #expect(finals.snapshot.top.first(where: \.isSelf)?.login == SampleServices.owner)
        #expect(finals.snapshot.state.competitorCount == 5)
    }

    @Test func switchedOffTheShareOpensOnTheLiveBoard() async throws {
        let model = try await sampleBoard(onNovember: 1)
        model.refresh.showFinalStandings(false)
        let request = try #require(model.boardShareRequest())
        #expect(request.styles.contains(.final))
        #expect(request.initialStyle == .board)
    }

    @Test func afterThe1stTheBoardOffersOnlyTheLiveStyles() async throws {
        let model = try await sampleBoard(onNovember: 2)
        let request = try #require(model.boardShareRequest())
        #expect(request.finals == nil)
        #expect(request.styles == [.board, .race, .rank, .list])
        #expect(request.initialStyle == .board)
    }

    /// A past month's Final standings, as the person view's past months share them: that style alone.
    @Test func aPastMonthSharesOnItsOwn() async throws {
        let model = try await sampleBoard(onNovember: 2)
        let finals = try #require(model.finalStandingsToShare(for: Self.october))
        #expect(finals.snapshot.top.map(\.medal) == [.gold, .silver, .bronze, nil, nil])
        let request = BoardShareRequest(finals: finals)
        #expect(request.styles == [.final])
        #expect(request.initialStyle == .final)
        // A month before your calendar starts has nothing to share.
        #expect(model.finalStandingsToShare(for: CalendarMonth(year: 2020, month: 1)) == nil)
    }

    @Test(arguments: BoardShareFormat.allCases)
    func finalStandingsRenderAtThePostedSize(format: BoardShareFormat) async throws {
        let model = try await sampleBoard(onNovember: 1)
        let finals = try #require(model.boardShareRequest()?.finals)
        let image = try #require(BoardShareRenderer.image(finals, format: format))
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        #expect(pixels == format.pixelSize)
        if let renderDirectory {
            try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
            try #require(image.pngData()).write(to: renderDirectory.appendingPathComponent("share-final-\(format.rawValue).png"))
        }
    }

    @Test func finalStandingsFileIsNamedForTheMonth() async throws {
        let model = try await sampleBoard(onNovember: 1)
        let finals = try #require(model.boardShareRequest()?.finals)
        let url = try BoardShareRenderer.file(finals, format: .square)
        #expect(url.lastPathComponent == "Committed-October-final-square.png")
        #expect(try Data(contentsOf: url).starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    /// The sheet as the Board opens it on the 1st (on Final standings), for review.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil), arguments: BoardShareFormat.allCases)
    func sheetOnThe1st(format: BoardShareFormat) async throws {
        let model = try await sampleBoard(onNovember: 1)
        let request = try #require(model.boardShareRequest())
        let window = try makeWindow(UIHostingController(rootView: BoardShareSheet(request: request, initialFormat: format)))
        try await save(window, name: "share-sheet-final-\(format.rawValue)")
    }

    @Test func finalStandingsCopyNamesTheMonth() {
        #expect(BoardShareCard.headline(Self.october) == "Who shipped more in October?")
        // A finished month's numbers are final, not "as of" a moment.
        #expect(BoardShareCard.finalLine(Self.october) == "Final · October 2026")
        #expect(BoardShareStyle.final.title == "Final standings")
    }

    private func makeWindow(_ controller: UIViewController) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.windowLevel = .normal + 1
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    private func save(_ window: UIWindow, name: String) async throws {
        let directory = try #require(renderDirectory)
        try await Task.sleep(for: .seconds(2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(image.pngData()).write(to: directory.appendingPathComponent("\(name).png"))
        window.isHidden = true
    }

    /// Today, you sixth of 27, as a real board has it: ten rows for the share's taller board.
    static let board = snapshot(selfRank: 6, window: .daily)

    /// Thirty days, you fourteenth of 27: below every format's rows.
    static let farDown = snapshot(selfRank: 14, window: .monthly)

    private static func snapshot(selfRank: Int, window: ContributionWindow) -> WidgetSnapshot {
        let logins = ["ines-volk", "devon", "alex", "odile-m", "ari-linden", "niko-vane", "bram-ott", "riley",
                      "casey", "morgan", "taylor-k", "jamie", "drew", "quinn", "avery"]
        let scale = window == .daily ? 1 : 30
        var rows: [WidgetSnapshot.Row] = []
        var people = logins
        people.insert("you", at: selfRank - 1)
        for (index, login) in people.prefix(BoardShareFormat.maxBoardRows).enumerated() {
            let count = max(0, (380 - index * 24) * scale)
            rows.append(.init(rank: index + 1, login: login, contributions: count,
                              movement: window == .daily && index == 2 ? 1 : 0, isSelf: login == "you"))
        }
        let mine = max(0, (380 - (selfRank - 1) * 24) * scale)
        return WidgetSnapshot(
            selfLogin: "you",
            state: LiveRankState(
                window: window.rawValue, rank: selfRank, competitorCount: 27, contributions: mine,
                above: .init(login: people[selfRank - 2], contributions: mine + 24 * scale, movementToday: 0),
                below: .init(login: people[selfRank], contributions: max(0, mine - 24 * scale), movementToday: 0),
                movementToday: 0, updatedAt: 1_794_172_920
            ),
            top: rows
        )
    }
}

@MainActor
private final class ImmediateBackgroundTime: BackgroundTimeProviding {
    func begin(_ name: String) -> Int { 0 }
    func end(_ token: Int) {}
}
