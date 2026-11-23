import Foundation
import SwiftUI
import Testing
import UIKit
@testable import CommitStandingsiOS

/// Share face-off in someone else's person view: you and them on one Window, contributions only,
/// as a square or a story. With `RENDER_DIR` set (`TEST_RUNNER_RENDER_DIR=/path`), the images are
/// also saved there as PNGs, for review.
@MainActor
@Suite(.serialized)
struct FaceOffShareTests {
    private let renderDirectory = ProcessInfo.processInfo.environment["RENDER_DIR"].map(URL.init(fileURLWithPath:))
    private static let english = Locale(identifier: "en_US")

    // MARK: Words and numbers

    @Test func eyebrowAndHeadlineFollowTheWindow() {
        #expect(Self.faceOff(.daily).eyebrow == "Head to head · Today")
        #expect(Self.faceOff(.weekly).eyebrow == "Head to head · 7 days")
        #expect(Self.faceOff(.monthly).eyebrow == "Head to head · 30 days")
        #expect(Self.faceOff(.daily).when == "today?")
        #expect(Self.faceOff(.weekly).when == "this week?")
        #expect(Self.faceOff(.monthly).when == "in 30 days?")
    }

    @Test func theLeaderIsLimeAndALevelRaceIsLimeForBoth() {
        let ahead = FaceOff(you: "addisonk", friend: "ezra-q", window: .weekly, yourTotal: 64, theirTotal: 52,
                            rangeText: "Nov 16 – Nov 22", locale: Self.english)
        #expect(ahead.youLead && !ahead.theyLead)
        let behind = FaceOff(you: "addisonk", friend: "ezra-q", window: .weekly, yourTotal: 40, theirTotal: 52,
                             rangeText: "Nov 16 – Nov 22", locale: Self.english)
        #expect(!behind.youLead && behind.theyLead)
        let level = FaceOff(you: "addisonk", friend: "ezra-q", window: .weekly, yourTotal: 52, theirTotal: 52,
                            rangeText: "Nov 16 – Nov 22", locale: Self.english)
        #expect(level.youLead && level.theyLead)
    }

    @Test func theBarDividesTheCombinedTotal() {
        let faceOff = FaceOff(you: "a", friend: "b", window: .daily, yourTotal: 30, theirTotal: 10,
                              rangeText: "Nov 22", locale: Self.english)
        #expect(faceOff.yourShare == 0.75)
        let nothing = FaceOff(you: "a", friend: "b", window: .daily, yourTotal: 0, theirTotal: 0,
                              rangeText: "Nov 22", locale: Self.english)
        #expect(nothing.yourShare == 0.5)
    }

    @Test func bigTotalsAreGrouped() {
        let faceOff = FaceOff(you: "a", friend: "b", window: .monthly, yourTotal: 1_204, theirTotal: 0,
                              rangeText: "", locale: Self.english)
        #expect(faceOff.formatted(faceOff.yourTotal) == "1,204")
    }

    // MARK: Where it shows

    @Test func someoneElsesLoadedBoardCanBeCompared() async throws {
        let model = await connectedBoard()
        model.showPerson("ezra-q")
        let person = try #require(model.shownPerson)
        for window in ContributionWindow.allCases {
            let faceOff = try #require(model.faceOff(with: "ezra-q", window: window))
            #expect(faceOff.you == SampleServices.owner)
            #expect(faceOff.friend == "ezra-q")
            // The Board's own numbers for each of you.
            let mine = try #require(model.store.history(for: SampleServices.owner))
            let theirs = try #require(model.store.history(for: "ezra-q"))
            #expect(faceOff.yourTotal == mine.total(for: window, asOf: Self.november10))
            #expect(faceOff.theirTotal == theirs.total(for: window, asOf: Self.november10))
        }
        // Over 30 days it agrees with the race on their view.
        let race = try #require(person.race)
        let monthly = try #require(model.faceOff(with: "ezra-q", window: .monthly))
        #expect(monthly.yourTotal == race.yourTotal)
        #expect(monthly.theirTotal == race.theirTotal)
    }

    @Test func todayIsOneDayAndTheOthersARange() async throws {
        let model = await connectedBoard()
        let today = try #require(model.faceOff(with: "ezra-q", window: .daily))
        #expect(!today.rangeText.contains("–"))
        #expect(try #require(model.faceOff(with: "ezra-q", window: .weekly)).rangeText.contains("–"))
        #expect(try #require(model.faceOff(with: "ezra-q", window: .monthly)).rangeText.contains("–"))
    }

    @Test func nothingToCompareOnYourOwnViewOrBeforeTheCalendarsLoad() async throws {
        let model = await connectedBoard()
        #expect(model.faceOff(with: SampleServices.owner, window: .weekly) == nil)
        let waiting = await connectedBoard(refreshed: false)
        #expect(waiting.faceOff(with: "ezra-q", window: .weekly) == nil)
    }

    @Test func compareWithListsEveryoneElse() async throws {
        let model = await connectedBoard()
        let people = model.faceOffPeople
        #expect(!people.contains(SampleServices.owner))
        #expect(people.contains("ezra-q"))
        #expect(people.contains("odile-m"))
    }

    // MARK: The image

    @Test(arguments: ContributionWindow.allCases, BoardShareFormat.allCases)
    func rendersAtTheFormatsSize(window: ContributionWindow, format: BoardShareFormat) throws {
        let faceOff = Self.faceOff(window)
        let image = try #require(ShareImageRenderer.image(FaceOffCard(faceOff: faceOff, format: format, savedAvatars: nil)))
        #expect(image.size.width * image.scale == format.pixelSize.width)
        #expect(image.size.height * image.scale == format.pixelSize.height)
        try save(image, as: "faceoff-\(window.rawValue)-\(format.rawValue)")
    }

    @Test(arguments: [(40, 52, "behind"), (52, 52, "level"), (0, 0, "empty"), (64, 0, "shutout")],
          BoardShareFormat.allCases)
    func rendersEveryOutcome(totals: (Int, Int, String), format: BoardShareFormat) throws {
        let faceOff = FaceOff(you: "addisonk", friend: "ezra-q", window: .weekly, yourTotal: totals.0,
                              theirTotal: totals.1, rangeText: "Nov 16 – Nov 22", locale: Self.english)
        let image = try #require(ShareImageRenderer.image(FaceOffCard(faceOff: faceOff, format: format, savedAvatars: nil)))
        #expect(image.size.width * image.scale == format.pixelSize.width)
        try save(image, as: "faceoff-\(totals.2)-\(format.rawValue)")
    }

    @Test func longLoginsAndBigTotalsStillFit() throws {
        let faceOff = FaceOff(you: "a-very-long-github-login", friend: "another-extremely-long-login",
                              window: .monthly, yourTotal: 12_480, theirTotal: 9_876,
                              rangeText: "Oct 24 – Nov 22", locale: Self.english)
        for format in BoardShareFormat.allCases {
            let image = try #require(ShareImageRenderer.image(FaceOffCard(faceOff: faceOff, format: format, savedAvatars: nil)))
            try save(image, as: "faceoff-long-\(format.rawValue)")
        }
    }

    @Test func fileIsAPNGNamedForThePeopleAndWindow() throws {
        let url = try FaceOffShareRenderer.file(Self.faceOff(.weekly), format: .square, savedAvatars: nil)
        #expect(url.lastPathComponent == "Committed-faceoff-addisonk-vs-ezra-q-7-days-square.png")
        #expect(try Data(contentsOf: url).starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    // MARK: Fixtures

    private func save(_ image: UIImage, as name: String) throws {
        guard let renderDirectory else { return }
        try FileManager.default.createDirectory(at: renderDirectory, withIntermediateDirectories: true)
        try #require(image.pngData()).write(to: renderDirectory.appendingPathComponent("\(name).png"))
    }

    static func faceOff(_ window: ContributionWindow) -> FaceOff {
        let totals: (Int, Int) = switch window {
        case .daily: (14, 9)
        case .weekly: (64, 52)
        case .monthly: (268, 241)
        }
        let range = switch window {
        case .daily: "Nov 22"
        case .weekly: "Nov 16 – Nov 22"
        case .monthly: "Oct 24 – Nov 22"
        }
        return FaceOff(you: "addisonk", friend: "ezra-q", window: window, yourTotal: totals.0, theirTotal: totals.1,
                       rangeText: range, locale: english)
    }

    nonisolated static let november10 = PersonViewAppTests.november10
    let widgets = RecordingWidgets()

    /// The Sample board's people and counts as a connected board (the screenshot fixture's graph),
    /// loaded unless `refreshed` is false.
    private func connectedBoard(refreshed: Bool = true) async -> AppModel {
        let now: @Sendable () -> Date = { Self.november10 }
        let model = AppModel(
            services: SampleServices.make(now: now),
            backgroundTime: FakeBackgroundTime(),
            liveRankActivities: FakeLiveRankActivities(),
            widgets: widgets.publisher,
            now: now
        )
        await model.auth.refreshIdentity()
        await model.roster.refresh(force: true)
        if refreshed { await model.refresh.refreshAll(reason: .manual) }
        return model
    }
}
