import Foundation
import SwiftUI
import Testing
import UIKit
@testable import CommitStandingsiOS

// Two more bare screens for the screenshot editor, from the Sample board pulled to refresh once
// (Ari Linden #3, just past Ezra Q, 2 behind Odile M), as `AppStoreScreenshots.render` uses, or
// from the owner's real board (`RealBoardTests`):
// - share-story: the Board share image itself, 1080 × 1920, as it lands in a story.
// - share-message: the square share image (1080 × 1080) sent to a group chat with your rank, as
//   texting it to friends looks.
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
        let sharedPeople = Set([shared.selfLogin] + shared.top.map(\.login))
        screens.append(AppStoreScreen(name: "share-story", png: story, people: sharedPeople))
        let square = try ShareImageRenderer.png(BoardShareCard(snapshot: shared, style: .board, format: .square, avatarCache: avatarCache))
        let squareImage = try #require(UIImage(data: square))
        screens.append(AppStoreScreen(name: "share-message", png: try opaquePNG(
            MessagesScreen(image: squareImage, caption: shareCaption(for: surfaces.liveRank),
                           sentAt: now.formatted(date: .omitted, time: .shortened))
                .environment(\.colorScheme, .dark)
        ), people: sharedPeople))

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

    /// What you'd type under the share image: your rank, and who's next to pass.
    static func shareCaption(for state: LiveRankState) -> String {
        guard let rank = state.rank else { return "Who shipped more today? 👀" }
        var caption = "#\(rank) of \(state.competitorCount) today."
        if let mine = state.contributions, let above = state.above, above.contributions > mine {
            caption += " \(above.contributions - mine) to pass \(above.login) 👀"
        }
        return caption
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

/// A group text at 9:41: you send the square share image and your rank, and a friend starts typing.
/// No one else's words: the replies are only the typing dots.
private struct MessagesScreen: View {
    let image: UIImage
    let caption: String
    let sentAt: String

    private let outgoing = Color(red: 0.04, green: 0.52, blue: 1.0)
    private let incoming = Color(white: 0.17)

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                Text("Today \(sentAt)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 340, height: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text(caption)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(outgoing, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .frame(maxWidth: 320, alignment: .trailing)
                Text("Delivered")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(alignment: .bottom, spacing: 8) {
                    Circle().fill(Color(white: 0.3)).frame(width: 30, height: 30)
                        .overlay(Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(.white.opacity(0.8)))
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(.white.opacity(i == 1 ? 0.75 : 0.45)).frame(width: 9, height: 9)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .background(incoming, in: Capsule())
                    Spacer()
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 14)
            composer
        }
        .foregroundStyle(.white)
        .frame(width: AppStoreScreenshots.size.width, height: AppStoreScreenshots.size.height)
        .background(.black)
        .overlay { DeviceChrome() }
    }

    private var header: some View {
        ZStack {
            HStack {
                Image(systemName: "chevron.left").font(.system(size: 22, weight: .semibold)).foregroundStyle(outgoing)
                Spacer()
            }
            .padding(.horizontal, 16)
            VStack(spacing: 5) {
                HStack(spacing: -12) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(Color(white: 0.28 + Double(i) * 0.06)).frame(width: 40, height: 40)
                            .overlay(Image(systemName: "person.fill").font(.system(size: 18)).foregroundStyle(.white.opacity(0.85)))
                            .overlay(Circle().stroke(.black, lineWidth: 2))
                    }
                }
                HStack(spacing: 3) {
                    Text("Shipping crew").font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(.top, 58)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.08))
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5) }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(white: 0.17)).frame(width: 36, height: 36)
                .overlay(Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.7)))
            HStack {
                Text("Message").font(.system(size: 17)).foregroundStyle(.white.opacity(0.35))
                Spacer()
                Image(systemName: "mic").font(.system(size: 17)).foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 40)
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

        #expect(screens.map(\.name) == ["share-story", "share-message", "notifications"])
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
