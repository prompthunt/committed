import Foundation
import Testing
@testable import CommitStandings

/// `committed://board?window=…` opens the Board on a Window. Live rank (#43) builds the same URL.
struct DeepLinkTests {
    @Test(arguments: [
        ("committed://board?window=daily", ContributionWindow.daily),
        ("committed://board?window=weekly", .weekly),
        ("committed://board?window=monthly", .monthly),
    ])
    func boardLinkOpensTheRequestedWindow(url: String, window: ContributionWindow) {
        #expect(DeepLink(url: URL(string: url)!) == .board(window: window))
    }

    @Test func boardLinkWithoutAWindowOpensTheBoardAsIs() {
        #expect(DeepLink(url: URL(string: "committed://board")!) == .board(window: nil))
        #expect(DeepLink(url: URL(string: "committed://board/")!) == .board(window: nil))
    }

    @Test func unknownWindowStillOpensTheBoardWithoutChangingIt() {
        #expect(DeepLink(url: URL(string: "committed://board?window=yearly")!) == .board(window: nil))
    }

    @Test func schemeAndHostAreCaseInsensitive() {
        #expect(DeepLink(url: URL(string: "Committed://Board?window=weekly")!) == .board(window: .weekly))
    }

    @Test(arguments: [
        "https://board?window=daily",
        "committed://people",
        "committed:board",
        "https://github.com/login/device",
    ])
    func otherURLsAreNotBoardLinks(url: String) {
        #expect(DeepLink(url: URL(string: url)!) == nil)
    }

    @Test func boardURLRoundTripsForEveryWindow() {
        for window in ContributionWindow.allCases {
            let url = DeepLink.board(window: window).url
            #expect(url.absoluteString == "committed://board?window=\(window.rawValue)")
            #expect(DeepLink(url: url) == .board(window: window))
        }
        #expect(DeepLink.board(window: nil).url.absoluteString == "committed://board")
    }
}
