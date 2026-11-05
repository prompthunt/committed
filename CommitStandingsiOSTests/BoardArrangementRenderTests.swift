import SwiftUI
import Testing
import UIKit
@testable import CommitStandingsiOS

/// Renders the real app (fixture data) at iPhone Duo sizes to PNGs, because the iPhone Duo
/// simulator can't be opened, folded, or split from the command line (see the #46 notes). The
/// window gets the size and horizontal size class of each layout; there's no fold region and no
/// vertical bars in these renders, since those come from the hardware and the scene.
///
/// Off unless `RENDER_DIR` is set; pass it to the test runner as
/// `TEST_RUNNER_RENDER_DIR=/path xcodebuild test -only-testing:CommitStandingsiOSTests/BoardArrangementRenderTests`.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil))
struct BoardArrangementRenderTests {
    /// Point sizes at 3x: outer display 1398 x 2034 px, inner display 2007 x 2853 px.
    enum Layout: String, CaseIterable {
        case closed, openLandscape, openPortrait, splitViewHalf

        var size: CGSize {
            switch self {
            case .closed: CGSize(width: 466, height: 678)
            case .openLandscape: CGSize(width: 951, height: 669)
            case .openPortrait: CGSize(width: 669, height: 951)
            case .splitViewHalf: CGSize(width: 475, height: 669)
            }
        }

        var sizeClass: UIUserInterfaceSizeClass {
            switch self {
            case .closed, .splitViewHalf: .compact
            case .openLandscape, .openPortrait: .regular
            }
        }
    }

    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RENDER_DIR"] ?? NSTemporaryDirectory())

    @Test(arguments: [AppTab.board, .people, .settings])
    func everyTabAtEveryLayout(tab: AppTab) async throws {
        let model = AppModel(services: ScreenshotFixture.services(), backgroundTime: NoBackgroundTime())
        model.selectedTab = tab
        let window = try makeWindow(model: model)
        for layout in Layout.allCases {
            try await render(window, layout: layout, name: "\(tab)-\(layout.rawValue)")
        }
        window.isHidden = true
    }

    /// Close → open → close on one window, the way a fold resizes the running app. The Window
    /// (7 days) and the tab carry across. Twenty people, so the board scrolls on both displays: the
    /// list keeps its scroll offset, but rows shift by the summary's height (about two rows) as the
    /// summary leaves the list on opening and returns on closing. Compare the renders.
    @Test func boardContinuityAcrossOpenAndClose() async throws {
        let model = AppModel(services: ScreenshotFixture.services(extraPeople: 14), backgroundTime: NoBackgroundTime())
        model.store.selectedWindow = .weekly
        let window = try makeWindow(model: model)
        try await render(window, layout: .closed, name: "continuity-1-closed")
        let list = try #require(firstScrollView(in: window, minimumContentHeight: 300))
        list.setContentOffset(CGPoint(x: 0, y: 600 - list.adjustedContentInset.top), animated: false)
        try await render(window, layout: .closed, name: "continuity-2-closed-scrolled")
        try await render(window, layout: .openLandscape, name: "continuity-3-open")
        try await render(window, layout: .closed, name: "continuity-4-closed-again")
        #expect(model.selectedTab == .board)
        #expect(model.store.selectedWindow == .weekly)
        window.isHidden = true
    }

    // MARK: - Helpers

    private func makeWindow(model: AppModel) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let root = RootView()
            .environment(model)
            .environment(model.store)
            .environment(model.refresh)
            .environment(model.auth)
            .environment(model.roster)
            .environment(model.services.notifications)
            .environment(\.loadsGitHubAvatars, false)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: root)
        window.windowLevel = .normal + 1
        window.isHidden = false
        return window
    }

    private func render(_ window: UIWindow, layout: Layout, name: String) async throws {
        window.rootViewController?.traitOverrides.horizontalSizeClass = layout.sizeClass
        window.frame = CGRect(origin: .zero, size: layout.size)
        window.layoutIfNeeded()
        // Fixture refreshes, list layout, and the summary pane's size report settle in this time.
        try await Task.sleep(for: .seconds(2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let data = try #require(image.pngData())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("render-\(name).png"))
    }

    private func firstScrollView(in view: UIView, minimumContentHeight: CGFloat) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > minimumContentHeight,
           scroll.contentSize.height > scroll.bounds.height {
            return scroll
        }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview, minimumContentHeight: minimumContentHeight) { return found }
        }
        return nil
    }
}

@MainActor
private final class NoBackgroundTime: BackgroundTimeProviding {
    func begin(_ name: String) -> Int { 0 }
    func end(_ token: Int) {}
}
