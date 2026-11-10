import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
@testable import CommitStandingsiOS

// The App Store screenshots' iPhone screens (#71): five 6.9" iPhone frames, 440 × 956 pt at 3x
// (1320 × 2868 px), and each frame's bare screen. The listing's frames are now made in the
// screenshot editor (appstore/screenshots) from the bare screens; these composed frames were 1.0's.
// Each is a caption band in the marketing site's style (ink, lime, Inter Tight, a lit field of
// contribution squares) over a phone showing an app screen or a system surface, all from the
// Sample board.
//
// - Board, Share board and People are the real app, hosted in a window at 440 × 956 pt with the
//   6.9" iPhone's safe areas and its bars at the bottom, then drawn into the phone.
// - Live rank and the widgets are the real Live Activity and widget views (`SystemSurfaceRendering`)
//   laid out on a Lock Screen and a Home Screen.
//
// The app screens run the Sample board's own services (`SampleServices`) as the app's graph, so
// the "Sample board · Connect GitHub" banner, a mode indicator rather than a feature, stays off
// these frames. Nothing in the app changes for it. Avatars are initials; nothing is fetched.

/// One App Store frame: its place in the set and its caption.
enum AppStoreFrame: Int, CaseIterable {
    case board = 1, liveRank, widgets, shareBoard, people

    var slug: String {
        switch self {
        case .board: "board"
        case .liveRank: "live-rank"
        case .widgets: "widgets"
        case .shareBoard: "share-board"
        case .people: "people"
        }
    }

    /// `01-board` …: App Store Connect orders an upload by file name.
    var name: String { String(format: "%02d-%@", rawValue, slug) }

    /// The site's folio: "01 · BOARD".
    var eyebrow: String {
        let label = switch self {
        case .board: "Board"
        case .liveRank: "Live rank"
        case .widgets: "Widgets"
        case .shareBoard: "Share board"
        case .people: "People"
        }
        return String(format: "%02d · %@", rawValue, label)
    }

    /// The headline's two lines: white, then lime, as on the site ("Who shipped more today?").
    var headline: (lead: String, accent: String) {
        switch self {
        case .board: ("Who shipped more", "today?")
        case .liveRank: ("Your rank on the", "Lock Screen.")
        case .widgets: ("The board on your", "Home Screen.")
        case .shareBoard: ("Share the board", "as an image.")
        case .people: ("Choose who's", "on your board.")
        }
    }

    var deck: String {
        switch self {
        case .board: "Friends ranked by GitHub Contributions."
        case .liveRank: "See who's ahead and how many to pass."
        case .widgets: "Your rank and the leaders at a glance."
        case .shareBoard: "A square post or a story."
        case .people: "From who you follow and your organizations."
        }
    }

    /// The caption as one line, for the manifest and the evidence.
    var caption: String { "\(headline.lead) \(headline.accent) \(deck)" }
}

/// One rendered App Store frame.
struct AppStoreFrameImage {
    let frame: AppStoreFrame
    let png: Data
    /// The screen alone, full size with its status bar and no caption or phone: the source the
    /// screenshot editor (`appstore/screenshots/`) frames itself.
    let screen: Data
    /// Every GitHub login the frame shows.
    let people: Set<String>

    var name: String { frame.name }
}

@MainActor
enum AppStoreScreenshots {
    /// The frame's size in points; at 3x, App Store Connect's 6.9" iPhone size.
    static let size = SurfaceSize.screen

    /// Renders the five frames in order.
    static func render() async throws -> [AppStoreFrameImage] {
        // The app on the Sample board's services, pulled to refresh once: Ari Linden has just
        // passed Ezra Q, #3 with a +1 chevron, as Live rank and the widgets show below.
        let model = AppModel(services: SampleServices.make(), backgroundTime: StillBackgroundTime())
        await model.sceneDidBecomeActive()
        await model.pullToRefresh()
        let surfaces = try await SampleBoardSurfaces.load()

        // The private-contributions tip is a one-time hint; it would sit half under the tab bar.
        let tipKey = "dismissedPrivateContribTip"
        let tipWasDismissed = UserDefaults.standard.object(forKey: tipKey)
        UserDefaults.standard.set(true, forKey: tipKey)
        defer { UserDefaults.standard.set(tipWasDismissed, forKey: tipKey) }

        let window = try AppScreenWindow(model: model)
        defer { window.close() }

        let board = try await window.capture()
        let boardPeople = Set(model.store.visibleCompetitors.map(\.username))

        let shared = try requireSnapshot(WidgetSnapshot.board(
            model.store, window: model.store.selectedWindow,
            rankDelta: { model.refresh.rankDelta(for: $0) }, now: .now,
            rows: BoardShareFormat.maxBoardRows
        ))
        let share = try await window.capture(presenting: BoardShareSheet(snapshot: shared, initialFormat: .story))

        // One person hidden, so People shows both the hide and the show control.
        model.store.setHidden(true, username: "bram-ott")
        model.selectedTab = .people
        let peopleScreen = try await window.capture()
        let peoplePeople = Set(model.store.competitors.map(\.username))

        let frames: [(AppStoreFrame, AnyView, Set<String>)] = [
            (.board, AnyView(AppScreen(image: board)), boardPeople),
            (.liveRank, AnyView(LockScreen(surfaces: surfaces)), shown(in: surfaces.liveRank, selfLogin: surfaces.selfLogin)),
            (.widgets, AnyView(HomeScreen(snapshot: surfaces.snapshot)), shown(in: surfaces.snapshot)),
            (.shareBoard, AnyView(AppScreen(image: share)), shown(in: shared)),
            (.people, AnyView(AppScreen(image: peopleScreen)), peoplePeople),
        ]
        return try frames.map { frame, screen, shown in
            AppStoreFrameImage(
                frame: frame,
                png: try opaquePNG(AppStoreFrameView(frame: frame) { screen }),
                screen: try opaquePNG(
                    screen
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, .dark)
                ),
                people: shown
            )
        }
    }

    /// App Store Connect refuses screenshots with an alpha channel, so the frame is flattened onto
    /// an RGB bitmap with no alpha and written with ImageIO (`UIImage.pngData()` keeps RGBA).
    private static func opaquePNG(_ view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw SurfaceRenderError.noImage }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = NSMutableData()
        guard let flattened = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw SurfaceRenderError.noImage }
        CGImageDestinationAddImage(destination, flattened, nil)
        guard CGImageDestinationFinalize(destination) else { throw SurfaceRenderError.noImage }
        return data as Data
    }

    private static func shown(in state: LiveRankState, selfLogin: String) -> Set<String> {
        Set([selfLogin] + [state.above?.login, state.below?.login].compactMap { $0 })
    }

    private static func shown(in snapshot: WidgetSnapshot) -> Set<String> {
        shown(in: snapshot.state, selfLogin: snapshot.selfLogin).union(snapshot.top.map(\.login))
    }

    private static func requireSnapshot(_ snapshot: WidgetSnapshot?) throws -> WidgetSnapshot {
        guard let snapshot else { throw SurfaceRenderError.noSampleBoard }
        return snapshot
    }
}

// MARK: - The frame

/// A frame: the caption band over the phone, on ink with the site's lit squares behind the
/// caption.
struct AppStoreFrameView<Screen: View>: View {
    let frame: AppStoreFrame
    @ViewBuilder let screen: Screen

    var body: some View {
        ZStack(alignment: .top) {
            Color.ink
            SquareFieldCanvas(light: UnitPoint(x: 0.5, y: 0), reach: 0.6, cell: 20, tone: FieldTone(brightness: 0.32))
                .frame(height: 520)
                .mask(LinearGradient(colors: [.white, .white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 0) {
                CaptionBand(frame: frame)
                    .padding(.top, 50)
                Spacer(minLength: 0)
                PhoneFrame { screen }
                    .padding(.bottom, 26)
            }
        }
        .frame(width: AppStoreScreenshots.size.width, height: AppStoreScreenshots.size.height)
        .environment(\.colorScheme, .dark)
    }
}

/// The site's heading block: a mono folio, a tight Inter Tight headline with its last line in
/// lime, and a soft line under it.
private struct CaptionBand: View {
    let frame: AppStoreFrame

    var body: some View {
        VStack(spacing: 0) {
            Text(frame.eyebrow)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color.lime)
            VStack(spacing: -5) {
                Text(frame.headline.lead).foregroundStyle(.white)
                Text(frame.headline.accent).foregroundStyle(Color.lime)
            }
            .font(.custom(CommittedType.displayFace, size: 40))
            .tracking(-40 * 0.03)
            .lineLimit(1)
            .padding(.top, 14)
            Text(frame.deck)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.soft)
                .lineLimit(1)
                .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

/// A plain phone: the 440 × 956 pt screen scaled into a black bezel with a hairline edge.
private struct PhoneFrame<Screen: View>: View {
    @ViewBuilder let screen: Screen

    static var screenWidth: CGFloat { 318 }
    private static var bezel: CGFloat { 7 }
    private static var cornerRadius: CGFloat { 62 }

    var body: some View {
        let size = AppStoreScreenshots.size
        let scale = Self.screenWidth / size.width
        let radius = Self.cornerRadius * scale
        screen
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .padding(Self.bezel)
            .background(Color(white: 0.02), in: RoundedRectangle(cornerRadius: radius + Self.bezel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius + Self.bezel, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5)
            }
            .shadow(color: Color.lime.opacity(0.14), radius: 36, y: 12)
    }
}

// MARK: - Screens (440 × 956 pt)

/// The status bar and Dynamic Island of a 6.9" iPhone at 9:41, with the home indicator.
private struct DeviceChrome: View {
    var body: some View {
        ZStack(alignment: .top) {
            Capsule().fill(.black).frame(width: 126, height: 37).padding(.top, 11)
            HStack {
                Text("9:41")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 120)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 120)
            }
            .padding(.top, 21)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            Capsule().fill(.white).frame(width: 150, height: 5).padding(.bottom, 8)
        }
        .foregroundStyle(.white)
    }
}

/// A capture of the app's window, under the status bar.
private struct AppScreen: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: AppStoreScreenshots.size.width, height: AppStoreScreenshots.size.height)
            .overlay { DeviceChrome() }
    }
}

/// A dark wallpaper lit with the site's contribution squares.
private struct Wallpaper: View {
    var light: UnitPoint

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.09), Color.ink], startPoint: .top, endPoint: .bottom)
            SquareFieldCanvas(light: light, reach: 0.6, cell: 24, gap: 5, tone: FieldTone(brightness: 0.5))
        }
    }
}

/// The Lock Screen at 9:41 with Committed's accessory widgets under the clock and Live rank's card
/// at the bottom.
private struct LockScreen: View {
    let surfaces: SampleBoardSurfaces

    var body: some View {
        ZStack {
            Wallpaper(light: UnitPoint(x: 0.5, y: 0.95))
            VStack(spacing: 0) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 70)
                Text("Sunday, November 8")
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

private struct LockScreenButton: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 21, weight: .medium))
            .frame(width: 54, height: 54)
            .background(.white.opacity(0.16), in: Circle())
    }
}

/// The Home Screen with every Committed widget: the rank card and the Committed Board widget,
/// then the medium and large widgets.
private struct HomeScreen: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ZStack {
            Wallpaper(light: UnitPoint(x: 0.3, y: 0.2))
            VStack(spacing: 24) {
                HStack(spacing: 24) {
                    HomeScreenWidget(size: SurfaceSize.small) { CommittedWidgetSmall(snapshot: snapshot) }
                    HomeScreenWidget(size: SurfaceSize.small) { CommittedWidgetBoardSmall(snapshot: snapshot) }
                }
                HomeScreenWidget(size: SurfaceSize.medium) { CommittedWidgetMedium(snapshot: snapshot) }
                HomeScreenWidget(size: SurfaceSize.large) { CommittedWidgetLarge(snapshot: snapshot) }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Circle().fill(.white).frame(width: 7, height: 7)
                    Circle().fill(.white.opacity(0.35)).frame(width: 7, height: 7)
                }
                .padding(.bottom, 40)
            }
            .padding(.top, 74)
        }
        .frame(width: AppStoreScreenshots.size.width, height: AppStoreScreenshots.size.height)
        .overlay { DeviceChrome() }
    }
}

// MARK: - Hosting the app

/// The real app in a window at 440 × 956 pt, with a 6.9" iPhone's safe areas (status bar and home
/// indicator) and its bars at the bottom rather than in the iPhone Duo's side bar.
@MainActor
private final class AppScreenWindow {
    private let window: UIWindow
    private let controller: UIViewController

    init(model: AppModel) throws {
        let scene = try Self.scene()
        let root = RootView()
            .environment(model)
            .environment(model.store)
            .environment(model.refresh)
            .environment(model.auth)
            .environment(model.roster)
            .environment(model.services.notifications)
            .environment(\.loadsGitHubAvatars, false)
            .toolbarVerticalBehavior(.disabled)
        controller = UIHostingController(rootView: root)
        window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.windowLevel = .normal + 1
        window.frame = CGRect(origin: .zero, size: AppStoreScreenshots.size)
        window.isHidden = false
        window.layoutIfNeeded()
        Self.matchSixPointNineInch(controller, in: window)
    }

    /// The window as drawn after the app settles (refreshes, list layout, the summary's size).
    func capture(settle: Duration = .seconds(2)) async throws -> UIImage {
        window.layoutIfNeeded()
        try await Task.sleep(for: settle)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    /// Presents `sheet` over the app, as the Board's Share button does, captures it, and dismisses.
    func capture(presenting sheet: some View) async throws -> UIImage {
        // The environment RootView gives a sheet it presents.
        let presented = UIHostingController(rootView: sheet
            .environment(\.standingRowStyle, .committed)
            .environment(\.avatarFallbackStyle, .committed)
            .environment(\.loadsGitHubAvatars, false)
            .tint(.lime)
            .preferredColorScheme(.dark)
            .toolbarVerticalBehavior(.disabled))
        Self.matchSixPointNineInch(presented, in: window)
        controller.present(presented, animated: false)
        let image = try await capture()
        controller.dismiss(animated: false)
        return image
    }

    func close() {
        window.isHidden = true
    }

    private static func scene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw SurfaceRenderError.noImage
        }
        return scene
    }

    /// A 6.9" iPhone's safe areas: 62 pt for the status bar and Dynamic Island, 34 pt for the home
    /// indicator, on top of whatever the host Simulator's window already has.
    private static func matchSixPointNineInch(_ controller: UIViewController, in window: UIWindow) {
        let base = window.safeAreaInsets
        controller.additionalSafeAreaInsets = UIEdgeInsets(
            top: max(0, 62 - base.top), left: 0, bottom: max(0, 34 - base.bottom), right: 0
        )
    }
}

@MainActor
private final class StillBackgroundTime: BackgroundTimeProviding {
    func begin(_ name: String) -> Int { 0 }
    func end(_ token: Int) {}
}
