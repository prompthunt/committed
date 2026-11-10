import SwiftUI
import Testing
@testable import CommitStandingsiOS

/// Every widget and Live rank presentation on the Sample board, with its numbers 13 min 36 sec
/// old (fresh) and 3 hours old (stale): the 20 pt Window, the counting-up age, and no "to pass"
/// line. The expanded and compact Dynamic Island are drawn from Live rank's own region views on a
/// black island shape. Renders, not captures: the Simulator can't show widgets on a Home Screen,
/// a Live Activity, or the Dynamic Island from here.
///
/// Off unless `RENDER_DIR` is set; pass it as `TEST_RUNNER_RENDER_DIR=/path`.

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["RENDER_DIR"] != nil))
struct WidgetRefreshRenderTests {
    private let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RENDER_DIR"] ?? NSTemporaryDirectory())
    private static let cases: [(name: String, age: Int, stale: Bool)] = [("fresh", 13 * 60 + 36, false), ("stale", 3 * 3600, true)]

    private func surfaces(age: Int) async throws -> (snapshot: WidgetSnapshot, live: LiveRankState, selfLogin: String) {
        let s = try await SampleBoardSurfaces.load()
        var snapshot = s.snapshot
        snapshot.state.updatedAt -= age
        var live = s.liveRank
        live.updatedAt -= age
        return (snapshot, live, s.selfLogin)
    }

    @Test func widgets() async throws {
        for c in Self.cases {
            let snapshot = try await surfaces(age: c.age).snapshot
            try SurfaceRenderer.write(
                SurfaceBackdrop {
                    HStack(spacing: 24) {
                        HomeScreenWidget(size: SurfaceSize.small, isStale: c.stale) { CommittedWidgetSmall(snapshot: snapshot) }
                        HomeScreenWidget(size: SurfaceSize.small, isStale: c.stale) { CommittedWidgetBoardSmall(snapshot: snapshot) }
                    }
                    HomeScreenWidget(size: SurfaceSize.medium, isStale: c.stale) { CommittedWidgetMedium(snapshot: snapshot) }
                    HomeScreenWidget(size: SurfaceSize.large, isStale: c.stale) { CommittedWidgetLarge(snapshot: snapshot) }
                    LockScreenAccessory(size: SurfaceSize.accessoryInline, plate: false) {
                        CommittedWidgetInline(snapshot: snapshot)
                    }
                    .environment(\.liveRankIsStale, c.stale)
                    HStack(spacing: 16) {
                        LockScreenAccessory(size: SurfaceSize.accessoryRectangular) {
                            CommittedWidgetRectangular(snapshot: snapshot).padding(.horizontal, 8)
                        }
                        LockScreenAccessory(size: SurfaceSize.accessoryCircular) {
                            CommittedWidgetCircular(snapshot: snapshot)
                        }
                    }
                    .environment(\.liveRankIsStale, c.stale)
                },
                name: "widgets-\(c.name)", to: directory
            )
        }
    }

    @Test func liveRank() async throws {
        for c in Self.cases {
            let (_, live, me) = try await surfaces(age: c.age)
            try SurfaceRenderer.write(
                SurfaceBackdrop {
                    LockScreenLiveActivity(state: live, selfLogin: me, isStale: c.stale)
                    IslandFrame {
                        LiveRankIslandLeading(state: live)
                    } trailing: {
                        LiveRankIslandTrailing(state: live)
                    } bottom: {
                        LiveRankIslandBottom(state: live, selfLogin: me)
                    }
                    .environment(\.liveRankIsStale, c.stale)
                    HStack(spacing: 24) {
                        CompactIsland {
                            LiveRankRankLabel(state: live, style: .compact)
                        } trailing: {
                            LiveRankCountLabel(state: live, style: .compact)
                        }
                        LiveRankSmall(state: live)
                            .frame(width: 200)
                            .background(Color.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .environment(\.liveRankIsStale, c.stale)
                },
                name: "live-rank-\(c.name)", to: directory
            )
        }
    }
}

/// The expanded Dynamic Island's regions on black, as iOS lays them out: the corners beside the
/// sensor, the bottom region under them. A drawing, not the system's island.
struct IslandFrame<Leading: View, Trailing: View, Bottom: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let bottom: Bottom

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                leading
                Spacer(minLength: 120)
                trailing
            }
            .frame(height: 36)
            bottom
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(width: SurfaceSize.liveActivityWidth)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
        .environment(\.colorScheme, .dark)
        .environment(\.loadsGitHubAvatars, false)
    }
}

/// The compact island: leading and trailing beside the sensor.
struct CompactIsland<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            leading
            Spacer(minLength: 100)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(width: 250, height: 37)
        .background(Capsule().fill(Color.black))
        .environment(\.colorScheme, .dark)
    }
}
