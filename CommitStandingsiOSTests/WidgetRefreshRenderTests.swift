import SwiftUI
import Testing
@testable import CommitStandingsiOS

/// Every widget and Live rank presentation on the Sample board, with its numbers 13 min 36 sec
/// old (fresh) and 3 hours old (stale): the 16 pt Window, the counting-up age, and no "to pass"
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

    private func surfaces(age: Int, window: ContributionWindow = .daily, justYou: Bool = false) async throws
        -> (snapshot: WidgetSnapshot, live: LiveRankState, selfLogin: String) {
        let s = try await SampleBoardSurfaces.load(window: window, justYou: justYou)
        var snapshot = s.snapshot
        snapshot.state.updatedAt -= age
        var live = s.liveRank
        live.updatedAt -= age
        return (snapshot, live, s.selfLogin)
    }

    @Test func widgets() async throws {
        for c in Self.cases {
            let snapshot = try await surfaces(age: c.age).snapshot
            try writeWidgets(snapshot, stale: c.stale, name: "widgets-\(c.name)")
        }
    }

    @Test func liveRank() async throws {
        for c in Self.cases {
            let (_, live, me) = try await surfaces(age: c.age)
            try writeLiveRank(live, selfLogin: me, stale: c.stale, name: "live-rank-\(c.name)")
        }
    }

    /// Nobody else on the board: no rank or rows, and your streak beside your count (#94's gap).
    @Test func justYou() async throws {
        for window in [ContributionWindow.daily, .monthly] {
            let (_, live, me) = try await surfaces(age: Self.cases[0].age, window: window, justYou: true)
            try writeLiveRank(live, selfLogin: me, stale: false, name: "live-rank-just-you-\(window.rawValue)")
        }
    }

    /// Your row never loses your name: the board's own row, 364 pt wide (the closed Duo's board
    /// beside the vertical bar), with logins from short to GitHub's 39-character maximum. The
    /// badge goes first, then your streak, then the name wraps; a rival's row keeps its streak.
    @Test func yourRowKeepsYourName() throws {
        func row(_ login: String, rank: Int, count: Int, isSelf: Bool, delta: Int, streak: Int) -> some View {
            StandingRow(rank: rank, competitor: Competitor(username: login, isSelf: isSelf),
                        standing: Standing(username: login, contributions: count, window: .daily,
                                           lastUpdated: .now, state: .loaded),
                        window: .daily, maxContributions: 140, rankDelta: delta, streak: streak)
        }
        try SurfaceRenderer.write(
            SurfaceBackdrop {
                VStack(spacing: 6) {
                    row("odile-m", rank: 2, count: 9, isSelf: false, delta: 0, streak: 371)
                    row("ari-linden", rank: 3, count: 7, isSelf: true, delta: 1, streak: 14)
                    row("ari", rank: 3, count: 7, isSelf: true, delta: 1, streak: 14)
                    row("addisonkowalski", rank: 12, count: 128, isSelf: true, delta: 2, streak: 41)
                    row("maximilian-bergstrom-hollingsworth-iii", rank: 12, count: 128, isSelf: true,
                        delta: -2, streak: 41)
                    row("maximilian-bergstrom-hollingsworth-iii", rank: 13, count: 120, isSelf: false,
                        delta: 0, streak: 6)
                }
                .frame(width: 364)
                .padding(.vertical, 8)
                .background(Color.ink)
                .environment(\.standingRowStyle, .committed)
                .environment(\.avatarFallbackStyle, .committed)
                .environment(\.loadsGitHubAvatars, false)
                .foregroundStyle(.white)
            },
            name: "your-row", to: directory
        )
    }

    private func writeWidgets(_ snapshot: WidgetSnapshot, stale: Bool, name: String) throws {
        try SurfaceRenderer.write(
            SurfaceBackdrop {
                HStack(spacing: 24) {
                    HomeScreenWidget(size: SurfaceSize.small, isStale: stale) { CommittedWidgetSmall(snapshot: snapshot) }
                    HomeScreenWidget(size: SurfaceSize.small, isStale: stale) { CommittedWidgetBoardSmall(snapshot: snapshot) }
                }
                HomeScreenWidget(size: SurfaceSize.medium, isStale: stale) { CommittedWidgetMedium(snapshot: snapshot) }
                HomeScreenWidget(size: SurfaceSize.large, isStale: stale) { CommittedWidgetLarge(snapshot: snapshot) }
                LockScreenAccessory(size: SurfaceSize.accessoryInline, plate: false) {
                    CommittedWidgetInline(snapshot: snapshot)
                }
                .environment(\.liveRankIsStale, stale)
                HStack(spacing: 16) {
                    LockScreenAccessory(size: SurfaceSize.accessoryRectangular) {
                        CommittedWidgetRectangular(snapshot: snapshot).padding(.horizontal, 8)
                    }
                    LockScreenAccessory(size: SurfaceSize.accessoryCircular) {
                        CommittedWidgetCircular(snapshot: snapshot)
                    }
                }
                .environment(\.liveRankIsStale, stale)
            },
            name: name, to: directory
        )
    }

    private func writeLiveRank(_ live: LiveRankState, selfLogin me: String, stale: Bool, name: String) throws {
        try SurfaceRenderer.write(
            SurfaceBackdrop {
                LockScreenLiveActivity(state: live, selfLogin: me, isStale: stale)
                IslandFrame {
                    LiveRankIslandLeading(state: live)
                } trailing: {
                    LiveRankIslandTrailing(state: live)
                } bottom: {
                    LiveRankIslandBottom(state: live, selfLogin: me)
                }
                .environment(\.liveRankIsStale, stale)
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
                .environment(\.liveRankIsStale, stale)
            },
            name: name, to: directory
        )
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
