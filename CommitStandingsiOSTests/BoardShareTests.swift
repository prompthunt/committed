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

    @Test(arguments: BoardShareStyle.allCases, BoardShareFormat.allCases)
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
        #expect(url.lastPathComponent == "Committed-30-days-board-story.png")
        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func storyHeadlineFollowsTheWindow() {
        #expect(BoardShareCard.headline(.daily) == "Who shipped more today?")
        #expect(BoardShareCard.headline(.weekly) == "Who shipped more this week?")
        #expect(BoardShareCard.headline(.monthly) == "Who shipped more this month?")
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

    /// Thirty days, you fourth of 27, and the leaders' counts far apart, as a real board has them.
    static let board = WidgetSnapshot(
        selfLogin: "you",
        state: LiveRankState(
            window: ContributionWindow.monthly.rawValue, rank: 4, competitorCount: 27, contributions: 6_581,
            above: .init(login: "alex", contributions: 8_666, movementToday: 0),
            below: .init(login: "sam-rivera", contributions: 3_246, movementToday: 0),
            movementToday: 0, updatedAt: Int(Date().timeIntervalSince1970)
        ),
        top: [
            .init(rank: 1, login: "maya-chen", contributions: 28_265, movement: 0, isSelf: false),
            .init(rank: 2, login: "devon", contributions: 9_308, movement: 0, isSelf: false),
            .init(rank: 3, login: "alex", contributions: 8_666, movement: 0, isSelf: false),
            .init(rank: 4, login: "you", contributions: 6_581, movement: 0, isSelf: true),
            .init(rank: 5, login: "sam-rivera", contributions: 3_246, movement: 0, isSelf: false),
            .init(rank: 6, login: "riley", contributions: 2_643, movement: 0, isSelf: false),
        ]
    )
}

@MainActor
private final class ImmediateBackgroundTime: BackgroundTimeProviding {
    func begin(_ name: String) -> Int { 0 }
    func end(_ token: Int) {}
}
