import AppKit
import SwiftUI
import Testing
@testable import CommitStandings

/// Renders the shared `StandingRow` as the Mac popover draws it, to PNGs, so a change to the row's
/// theming can be checked against the Mac's look pixel for pixel: render before and after, then
/// compare the files. `StandingRow` is shared with the iPhone app, which restyles it through the
/// environment; the Mac must not change.
///
/// Off unless `RENDER_DIR` is set: `TEST_RUNNER_RENDER_DIR=/path xcodebuild test -scheme
/// CommitStandings -only-testing:CommitStandingsTests/StandingRowRenderTests`.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil))
struct StandingRowRenderTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RENDER_DIR"] ?? NSTemporaryDirectory())

    @Test(arguments: [ColorScheme.dark, .light])
    func macRows(scheme: ColorScheme) throws {
        let updated = Date(timeIntervalSince1970: 1_793_849_760)
        func standing(_ username: String, _ contributions: Int, _ state: LoadState = .loaded) -> Standing {
            Standing(username: username, contributions: contributions, window: .daily, lastUpdated: updated, state: state)
        }
        let board = VStack(spacing: 2) {
            StandingRow(rank: 1, competitor: Competitor(username: "ines-volk", isSelf: false),
                        standing: standing("ines-volk", 12), window: .daily, maxContributions: 12, rankDelta: 2)
            StandingRow(rank: 2, competitor: Competitor(username: "ari-linden", isSelf: true),
                        standing: standing("ari-linden", 7), window: .daily, maxContributions: 12, rankDelta: 1)
            StandingRow(rank: 3, competitor: Competitor(username: "ezra-q", isSelf: false),
                        standing: standing("ezra-q", 3), window: .daily, maxContributions: 12, rankDelta: -1)
            StandingRow(rank: 4, competitor: Competitor(username: "niko-vane", isSelf: false),
                        standing: Standing(username: "niko-vane", contributions: 0, window: .daily,
                                           lastUpdated: .distantPast, state: .failed("offline")),
                        window: .daily, maxContributions: 12)
            StandingRow(rank: 12, competitor: Competitor(username: "a-very-long-github-username-here", isSelf: false),
                        standing: standing("a-very-long-github-username-here", 0), window: .daily, maxContributions: 12)
        }
        .padding(10)
        .frame(width: 340)
        .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
        .environment(\.colorScheme, scheme)
        .environment(\.loadsGitHubAvatars, false)

        let renderer = ImageRenderer(content: board)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appending(path: "mac-standing-rows-\(scheme == .dark ? "dark" : "light").png"))
    }
}
