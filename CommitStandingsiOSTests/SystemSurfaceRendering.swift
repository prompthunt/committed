import SwiftUI
import UIKit
@testable import CommitStandingsiOS

// Renders of what Committed shows outside the app: the Home Screen and Lock Screen widgets, the
// Committed Board widget and Live rank's Lock Screen card. The Simulator can't place widgets on a
// Home Screen or draw a Live Activity from the command line, so evidence and the App Store frames
// render the real views with ImageRenderer instead. They are renders, not runtime captures.
//
// Three reusable parts:
// - `SampleBoardSurfaces.load()` runs the Sample board through `AppModel` and returns what it
//   published: the widget snapshot and the Live rank activity's state.
// - `SurfaceSize` and the frames (`HomeScreenWidget`, `LockScreenAccessory`,
//   `LockScreenLiveActivity`) put a view at its size on a 6.9" iPhone, with WidgetKit's margins.
// - `SurfaceRenderer.png` / `.write` turn any composition into a PNG at 3x.

// MARK: - Sample board data

/// What the Sample board publishes to the system surfaces, taken from a real `AppModel` run.
@MainActor
struct SampleBoardSurfaces {
    /// What the widgets read from the App Group.
    let snapshot: WidgetSnapshot
    /// Live rank's activity content (the Lock Screen card, the Dynamic Island).
    let liveRank: LiveRankState
    let selfLogin: String

    /// Starts the Sample board on a not-connected app, then (by default) pulls to refresh once, so
    /// Ari Linden has just passed Ezra Q: #3 with a +1 chevron. `refreshed: false` keeps the first
    /// load (#4). The clock is real, so "updated" ages read "now".
    static func load(refreshed: Bool = true) async throws -> SampleBoardSurfaces {
        let activities = FakeLiveRankActivities()
        let widgets = RecordingWidgets()
        let notConnected = CommittedServices(
            store: StandingsStore(persistence: InMemoryCompetitorPersistence()),
            credentials: InMemoryGitHubCredentialStore(token: nil)
        )
        let model = AppModel(
            services: notConnected, backgroundTime: FakeBackgroundTime(),
            liveRankActivities: activities, widgets: widgets.publisher
        )
        await model.startSampleBoard()
        if refreshed { await model.pullToRefresh() }
        guard let snapshot = widgets.last, let activity = activities.running.first else {
            throw SurfaceRenderError.noSampleBoard
        }
        return SampleBoardSurfaces(snapshot: snapshot, liveRank: activity.state, selfLogin: activity.selfLogin)
    }
}

enum SurfaceRenderError: Error {
    case noSampleBoard
    case noImage
}

// MARK: - Sizes

/// Widget and Live Activity sizes in points on a 6.9" iPhone (440 × 956 pt), the App Store size.
enum SurfaceSize {
    static let screen = CGSize(width: 440, height: 956)
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large = CGSize(width: 364, height: 382)
    static let accessoryRectangular = CGSize(width: 172, height: 76)
    static let accessoryCircular = CGSize(width: 76, height: 76)
    static let accessoryInline = CGSize(width: 257, height: 26)
    /// The Lock Screen card's width; its height follows the content (iOS caps it at 160).
    static let liveActivityWidth: CGFloat = 408
    /// WidgetKit's default content margin for system sizes.
    static let widgetMargin: CGFloat = 16
    static let widgetCornerRadius: CGFloat = 24
}

// MARK: - Frames

/// A system-size widget as the Home Screen draws it: ink background, rounded corners, WidgetKit's
/// 16 pt margins, dark. Wrap `CommittedWidgetSmall`, `…Medium`, `…Large`, `…BoardSmall` or
/// `CommittedWidgetConnect`.
struct HomeScreenWidget<Content: View>: View {
    let size: CGSize
    var isStale = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(SurfaceSize.widgetMargin)
            .frame(width: size.width, height: size.height)
            .background(Color.ink)
            .clipShape(RoundedRectangle(cornerRadius: SurfaceSize.widgetCornerRadius, style: .continuous))
            .environment(\.liveRankIsStale, isStale)
            .environment(\.colorScheme, .dark)
            .environment(\.loadsGitHubAvatars, false)
    }
}

/// A Lock Screen accessory widget, drawn in white over a translucent plate as the Lock Screen
/// tints it. Wrap `CommittedWidgetRectangular`, `…Inline` or `…Circular`.
struct LockScreenAccessory<Content: View>: View {
    let size: CGSize
    var plate = true
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(.white)
            .frame(width: size.width, height: size.height)
            .background {
                if plate {
                    if size == SurfaceSize.accessoryCircular {
                        Circle().fill(.white.opacity(0.14))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08))
                    }
                }
            }
            .environment(\.colorScheme, .dark)
    }
}

/// Live rank's Lock Screen card (`LiveRankLockScreen`) at the Lock Screen's width, on its ink tint
/// with the system's rounded corners.
struct LockScreenLiveActivity: View {
    let state: LiveRankState
    let selfLogin: String
    var isStale = false

    var body: some View {
        LiveRankLockScreen(state: state, selfLogin: selfLogin)
            .frame(width: SurfaceSize.liveActivityWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.ink)
            .clipShape(RoundedRectangle(cornerRadius: SurfaceSize.widgetCornerRadius, style: .continuous))
            .environment(\.liveRankIsStale, isStale)
            .environment(\.loadsGitHubAvatars, false)
    }
}

/// A dark, wallpaper-like backdrop for laying surfaces out the way a Lock Screen or Home Screen
/// would, padded and stacked. Plain on purpose: it shouldn't pass for a device capture.
struct SurfaceBackdrop<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(24)
            .background(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)],
                                       startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Rendering

@MainActor
enum SurfaceRenderer {
    /// The view as PNG data at `scale` (3x, the 6.9" iPhone's).
    static func png(_ view: some View, scale: CGFloat = 3) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let data = renderer.uiImage?.pngData() else { throw SurfaceRenderError.noImage }
        return data
    }

    /// Writes `<name>.png` into `directory` and returns its URL.
    @discardableResult
    static func write(_ view: some View, name: String, to directory: URL, scale: CGFloat = 3) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        try png(view, scale: scale).write(to: url, options: .atomic)
        return url
    }
}
