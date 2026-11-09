import Foundation
import Testing
import UIKit
@testable import CommitStandingsiOS

/// The App Store screenshots (#71): five 6.9" iPhone frames, each a caption band over an app
/// screen or system surface, rendered from the Sample board. They're renders, not runtime
/// captures: the only Simulator on iOS 27.1 is the iPhone Duo, which isn't an App Store size.
///
/// Always runs, to keep the frames at the size App Store Connect takes and on sample data. With
/// `RENDER_DIR` set (`TEST_RUNNER_RENDER_DIR=/path`), it also writes `01-board.png` …
/// `05-people.png` there; `docs/screenshots/app-store/README.md` says how to publish them.
@MainActor
@Suite(.serialized)
struct AppStoreScreenshotTests {
    /// Everyone the Sample board shows. Written out, not read from `SampleServices`, so a change to
    /// the sample people (or real people slipping in) fails here.
    private static let samplePeople: Set<String> = ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"]

    @Test func fiveFramesAtTheSixPointNineInchSizeFromTheSampleBoard() async throws {
        GitHubTrafficRecorder.start()
        defer { GitHubTrafficRecorder.stop() }
        let control = try #require(URL(string: "https://api.github.com/recorder-check/\(UUID().uuidString)"))
        _ = try? await URLSession.shared.data(from: control)
        #expect(GitHubTrafficRecorder.requests.contains(control))

        let frames = try await AppStoreScreenshots.render()

        #expect(frames.map(\.name) == ["01-board", "02-live-rank", "03-widgets", "04-share-board", "05-people"])
        for frame in frames {
            let image = try #require(UIImage(data: frame.png)?.cgImage, "\(frame.name) isn't a PNG")
            #expect(image.width == 1320 && image.height == 2868, "\(frame.name) is \(image.width) × \(image.height)")
            // App Store Connect takes no alpha channel.
            #expect([.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo), "\(frame.name) has an alpha channel")
            #expect(!frame.people.isEmpty, "\(frame.name) shows nobody")
            #expect(frame.people.isSubset(of: Self.samplePeople), "\(frame.name) shows \(frame.people.subtracting(Self.samplePeople))")
        }
        // Avatars are initials: nothing was fetched from GitHub while rendering.
        #expect(GitHubTrafficRecorder.unexpectedRequests.isEmpty)

        if let directory = ProcessInfo.processInfo.environment["RENDER_DIR"].map(URL.init(fileURLWithPath:)) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for frame in frames {
                try frame.png.write(to: directory.appendingPathComponent("\(frame.name).png"), options: .atomic)
            }
        }
    }
}
