import SwiftUI
import Testing
@testable import CommitStandingsiOS

/// Live rank and the widgets on the Sample board (#68), rendered from what the Sample board
/// publishes (`SampleBoardSurfaces`): Live rank's Lock Screen card, the Home Screen widgets, the
/// Lock Screen widgets, the Committed Board widget, and the widgets after leaving. Renders, not
/// captures: the Simulator can't show a Live Activity or widgets on a Home Screen from here.
///
/// Off unless `RENDER_DIR` is set; pass it as `TEST_RUNNER_RENDER_DIR=/path`.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil))
struct SampleBoardSurfaceRenderTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RENDER_DIR"] ?? NSTemporaryDirectory())

    @Test func liveRankOnTheLockScreen() async throws {
        let first = try await SampleBoardSurfaces.load(refreshed: false)
        let moved = try await SampleBoardSurfaces.load()
        try SurfaceRenderer.write(
            SurfaceBackdrop {
                LockScreenLiveActivity(state: first.liveRank, selfLogin: first.selfLogin)
                LockScreenLiveActivity(state: moved.liveRank, selfLogin: moved.selfLogin)
            },
            name: "live-rank-lock-screen", to: directory
        )
    }

    @Test func homeScreenWidgets() async throws {
        let surfaces = try await SampleBoardSurfaces.load()
        let snapshot = surfaces.snapshot
        try SurfaceRenderer.write(
            SurfaceBackdrop {
                HStack(spacing: 24) {
                    HomeScreenWidget(size: SurfaceSize.small) { CommittedWidgetSmall(snapshot: snapshot) }
                    HomeScreenWidget(size: SurfaceSize.small) { CommittedWidgetBoardSmall(snapshot: snapshot) }
                }
                HomeScreenWidget(size: SurfaceSize.medium) { CommittedWidgetMedium(snapshot: snapshot) }
                HomeScreenWidget(size: SurfaceSize.large) { CommittedWidgetLarge(snapshot: snapshot) }
            },
            name: "home-screen-widgets", to: directory
        )
    }

    @Test func lockScreenWidgets() async throws {
        let snapshot = try await SampleBoardSurfaces.load().snapshot
        try SurfaceRenderer.write(
            SurfaceBackdrop {
                LockScreenAccessory(size: SurfaceSize.accessoryInline, plate: false) {
                    CommittedWidgetInline(snapshot: snapshot)
                }
                HStack(spacing: 16) {
                    LockScreenAccessory(size: SurfaceSize.accessoryRectangular) {
                        CommittedWidgetRectangular(snapshot: snapshot).padding(.horizontal, 8)
                    }
                    LockScreenAccessory(size: SurfaceSize.accessoryCircular) {
                        CommittedWidgetCircular(snapshot: snapshot)
                    }
                }
            },
            name: "lock-screen-widgets", to: directory
        )
    }

    @Test func boardWidget() async throws {
        let first = try await SampleBoardSurfaces.load(refreshed: false).snapshot
        let moved = try await SampleBoardSurfaces.load().snapshot
        try SurfaceRenderer.write(
            SurfaceBackdrop {
                HStack(spacing: 24) {
                    HomeScreenWidget(size: SurfaceSize.small) { CommittedWidgetBoardSmall(snapshot: first) }
                    HomeScreenWidget(size: SurfaceSize.small) { CommittedWidgetBoardSmall(snapshot: moved) }
                }
            },
            name: "board-widget", to: directory
        )
    }

    /// Leaving publishes nil: every widget asks you to connect GitHub.
    @Test func widgetsAfterLeaving() throws {
        let none: WidgetSnapshot? = nil
        try SurfaceRenderer.write(
            SurfaceBackdrop {
                HStack(spacing: 24) {
                    HomeScreenWidget(size: SurfaceSize.small) { CommittedWidgetConnect() }
                    HomeScreenWidget(size: SurfaceSize.small) { CommittedWidgetConnect() }
                }
                HStack(spacing: 16) {
                    LockScreenAccessory(size: SurfaceSize.accessoryRectangular) {
                        CommittedWidgetRectangular(snapshot: none).padding(.horizontal, 8)
                    }
                    LockScreenAccessory(size: SurfaceSize.accessoryCircular) {
                        CommittedWidgetCircular(snapshot: none)
                    }
                }
            },
            name: "widgets-after-leaving", to: directory
        )
    }
}
