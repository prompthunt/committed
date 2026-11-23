import Foundation
import SwiftUI
import Testing
import UIKit
@testable import CommitStandingsiOS

// Two more bare screens for the screenshot editor, from the Sample board pulled to refresh once
// (Ari Linden #3, just past Ezra Q, 2 behind Odile M), as `AppStoreScreenshots.render` uses, or
// from the owner's real board (`RealBoardTests`):
// - share-story: the Board share image itself, 1080 × 1920, as it lands in a story or a message.
// - notifications: the Lock Screen with Committed's accessory widgets, and the notifications that
//   board sends at that moment, in the app's own words, above Live rank.

@MainActor
extension AppStoreScreenshots {
    static func listingScreens() async throws -> [AppStoreScreen] {
        let model = AppModel(services: SampleServices.make(), backgroundTime: StillBackgroundTime())
        await model.sceneDidBecomeActive()
        await model.pullToRefresh()
        // No saved avatars on the Sample board: initials, as its own Share board draws them.
        return try listingScreens(model: model, surfaces: try await SampleBoardSurfaces.load(), now: .now,
                                  avatarCache: nil, date: "Sunday, November 8")
    }

    /// The share image of `model`'s board as of `now`, and the Lock Screen for `surfaces` (its
    /// widgets and Live rank) dated `date`, the day of the board by default.
    static func listingScreens(model: AppModel, surfaces: SampleBoardSurfaces, now: Date,
                               avatarCache: AvatarCache? = .shared, date: String? = nil) throws -> [AppStoreScreen] {
        var screens: [AppStoreScreen] = []
        let shared = try #require(WidgetSnapshot.board(
            model.store, window: model.store.selectedWindow,
            rankDelta: { model.refresh.rankDelta(for: $0) }, now: now,
            rows: BoardShareFormat.maxBoardRows
        ))
        let story = try ShareImageRenderer.png(BoardShareCard(snapshot: shared, style: .board, format: .story, avatarCache: avatarCache))
        screens.append(AppStoreScreen(name: "share-story", png: story, people: Set([shared.selfLogin] + shared.top.map(\.login))))

        let live = surfaces.liveRank
        let day = date ?? now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        screens.append(AppStoreScreen(
            name: "notifications",
            png: try opaquePNG(NotificationsLockScreen(surfaces: surfaces, banners: notifications(for: live), date: day)
                .environment(\.colorScheme, .dark)),
            people: Set([surfaces.selfLogin] + [live.above?.login, live.below?.login].compactMap { $0 })
        ))
        return screens
    }

    /// What Committed sends for Live rank's `state`, in the app's and the relay's words: the pass
    /// that just happened (you moved up today and the person now under you moved down), then a
    /// close call on the person above you when you're within its reach (`closeCalls.ts`: 3, or 5%
    /// of their count when that's more).
    static func notifications(for state: LiveRankState) -> [NotificationBanner] {
        guard let mine = state.contributions else { return [] }
        var banners: [NotificationBanner] = []
        if state.movementToday > 0, let below = state.below, below.movementToday < 0 {
            let copy = NotificationService.copy(for: RankChangeEvent(
                rivalUsername: below.login, direction: .iPassedRival,
                rivalContributions: below.contributions, myContributions: mine
            ))
            banners.append(NotificationBanner(title: copy.title, message: copy.body))
        }
        if let above = state.above {
            let toPass = above.contributions - mine
            let reach = max(3, Int((Double(above.contributions) / 20).rounded(.up)))
            if toPass > 0, toPass <= reach {
                let window = ContributionWindow(rawValue: state.window)?.shortTitle ?? "Today"
                banners.append(NotificationBanner(
                    title: "Close call: \(toPass) to pass \(above.login)",
                    message: "You're at \(mine), they're at \(above.contributions) · \(window)"
                ))
            }
        }
        return banners
    }
}

/// A notification on the Lock Screen: Committed's icon, the title, "now" and the body.
struct NotificationBanner: View, Equatable {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppMark(size: 38, glows: false)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("now").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                Text(message).font(.system(size: 15)).foregroundStyle(.white.opacity(0.92)).lineLimit(2)
            }
        }
        .padding(14)
        .frame(width: SurfaceSize.liveActivityWidth, alignment: .leading)
        .background(Color(white: 0.16).opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// The Lock Screen at 9:41: Committed's accessory widgets under the clock, then the notifications
/// above Live rank's card.
private struct NotificationsLockScreen: View {
    let surfaces: SampleBoardSurfaces
    let banners: [NotificationBanner]
    let date: String

    var body: some View {
        ZStack {
            Wallpaper(light: UnitPoint(x: 0.5, y: 0.95))
            VStack(spacing: 0) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 70)
                Text(date)
                    .font(.system(size: 21, weight: .semibold))
                    .padding(.top, 10)
                Text("9:41")
                    .font(.system(size: 112, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.top, -10)
                HStack(spacing: 14) {
                    LockScreenAccessory(size: SurfaceSize.accessoryRectangular) {
                        CommittedWidgetRectangular(snapshot: surfaces.snapshot).padding(.horizontal, 8)
                    }
                    LockScreenAccessory(size: SurfaceSize.accessoryCircular) {
                        CommittedWidgetCircular(snapshot: surfaces.snapshot)
                    }
                }
                .padding(.top, 2)
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    ForEach(banners.indices, id: \.self) { banners[$0] }
                }
                .padding(.bottom, 10)
                LockScreenLiveActivity(state: surfaces.liveRank, selfLogin: surfaces.selfLogin)
                HStack {
                    LockScreenButton(symbol: "flashlight.off.fill")
                    Spacer()
                    LockScreenButton(symbol: "camera.fill")
                }
                .padding(.horizontal, 46)
                .padding(.top, 28)
                .padding(.bottom, 44)
            }
            .foregroundStyle(.white)
        }
        .frame(width: AppStoreScreenshots.size.width, height: AppStoreScreenshots.size.height)
        .overlay { DeviceChrome() }
    }
}

@MainActor
@Suite(.serialized)
struct AppStoreListingScreenTests {
    private static let samplePeople: Set<String> = ["ines-volk", "odile-m", "ezra-q", "ari-linden", "bram-ott"]

    @Test func theListingScreensFromTheSampleBoard() async throws {
        GitHubTrafficRecorder.start()
        defer { GitHubTrafficRecorder.stop() }

        let screens = try await AppStoreScreenshots.listingScreens()

        #expect(screens.map(\.name) == ["share-story", "notifications"])
        for screen in screens {
            let image = try #require(UIImage(data: screen.png)?.cgImage, "\(screen.name) isn't a PNG")
            let expected = screen.name == "share-story" ? (1080, 1920) : (1320, 2868)
            #expect(image.width == expected.0 && image.height == expected.1, "\(screen.name) is \(image.width) × \(image.height)")
            #expect(screen.people.isSubset(of: Self.samplePeople), "\(screen.name) shows \(screen.people.subtracting(Self.samplePeople))")
        }
        #expect(GitHubTrafficRecorder.unexpectedRequests.isEmpty)

        if let directory = ProcessInfo.processInfo.environment["RENDER_DIR"].map(URL.init(fileURLWithPath:)) {
            try AppStoreScreenshots.write(screens, to: directory.appendingPathComponent("screens"), prefix: "listing-")
        }
    }

    /// The Lock Screen says only what that board sends: Ari has just passed Ezra Q and is 2 behind
    /// Odile M on Today, so a pass and a close call, in the shipped copy.
    @Test func theLockScreenShowsWhatThatBoardSends() async throws {
        let state = try await SampleBoardSurfaces.load().liveRank
        let banners = AppStoreScreenshots.notifications(for: state)
        let mine = try #require(state.contributions)
        let above = try #require(state.above)
        let below = try #require(state.below)
        #expect(banners == [
            NotificationBanner(title: "🎉 You passed \(below.login)!",
                               message: "You're ahead \(mine)–\(below.contributions). Keep climbing!"),
            NotificationBanner(title: "Close call: \(above.contributions - mine) to pass \(above.login)",
                               message: "You're at \(mine), they're at \(above.contributions) · Today"),
        ])
    }
}
