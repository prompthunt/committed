import Testing
import Foundation
@testable import CommitStandingsiOS

/// `committed://board?window=<daily|weekly|monthly>` opens the Board on that Window.
@MainActor
struct DeepLinkTests {

    private func app() -> AppModel {
        AppModel(.testing(contributions: StubContributions()))
    }

    @Test func aBoardLinkOpensTheBoardTabOnTheRequestedWindow() throws {
        let app = app()
        app.selectedTab = .settings

        let handled = app.open(try #require(URL(string: "committed://board?window=weekly")))

        #expect(handled)
        #expect(app.selectedTab == .board)
        #expect(app.store.selectedWindow == .weekly)
    }

    @Test func aBoardLinkWithoutAWindowOpensTheBoardAndKeepsTheCurrentWindow() throws {
        let app = app()
        app.selectedTab = .people
        app.store.selectedWindow = .monthly

        #expect(app.open(try #require(URL(string: "committed://board"))))

        #expect(app.selectedTab == .board)
        #expect(app.store.selectedWindow == .monthly)
    }

    @Test(arguments: [
        "committed://board?window=yearly",
        "committed://people",
        "https://board?window=weekly",
    ])
    func linksItDoesNotUnderstandChangeNothing(_ link: String) throws {
        let app = app()
        app.selectedTab = .people
        app.store.selectedWindow = .monthly

        #expect(!app.open(try #require(URL(string: link))))

        #expect(app.selectedTab == .people)
        #expect(app.store.selectedWindow == .monthly)
    }
}
