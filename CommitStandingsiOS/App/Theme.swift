import SwiftUI
import UIKit

// The iPhone half of the theme (#51). Tokens, type, squares, and the trophy live in the shared
// `CommittedTheme.swift` (also used by Live rank); this file holds what only the app needs.

extension StandingRowStyle {
    /// The board's row on iPhone: Inter Tight numerals, the site's square ramp, and your row in
    /// lime. Same row as the Mac, restyled.
    static let committed = StandingRowStyle(
        rankFont: CommittedType.numeral(15, relativeTo: .subheadline),
        rankColor: .muted,
        rankWidthScale: 1.25,
        nameFont: .body,
        selfNameFont: .body.weight(.semibold),
        countFont: CommittedType.numeral(19, relativeTo: .body),
        selfCountFont: CommittedType.display(19, relativeTo: .body),
        // Lime like the hero's count: your number reads the same everywhere.
        selfCountColor: .lime,
        avatarSize: 30,
        spacing: 12,
        horizontalPadding: 12,
        verticalPadding: 11,
        accent: .lime,
        badgeFont: .caption.weight(.bold),
        badgeForeground: .onLime,
        badgeFillOpacity: 1,
        selfFillOpacity: 0.07,
        selfStrokeOpacity: 0.32,
        cornerRadius: 14,
        movementUpColor: .lime,
        // Losing a place is news: brighter than secondary text, never alarm-orange.
        movementDownColor: .soft,
        movementFont: .caption2.weight(.heavy),
        squares: .ramp(Color.rowSquares, size: 14)
    )
}

extension AvatarFallbackStyle {
    /// A tile with a hairline and soft initials, instead of a saturated colored circle.
    static let committed = AvatarFallbackStyle(fill: .raised, stroke: .hairline, text: .soft)
}

// MARK: - Surfaces

extension View {
    /// A scrolling screen on the ink page instead of the system's grouped gray.
    func inkScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.ink)
    }

    /// Caps a scrolling list or form at a readable width, centered, so rows and their controls
    /// don't stretch across the open iPhone Duo display. `minimumMargin` is the container's own
    /// side margin at phone widths (20 for an inset-grouped `Form`, 0 for a plain `List`), which
    /// this replaces.
    func readableContentWidth(_ maxWidth: CGFloat = 640, minimumMargin: CGFloat) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth, minimumMargin: minimumMargin))
    }

    /// The site's card: a tile with a hairline edge.
    func tileCard(cornerRadius: CGFloat = 20) -> some View {
        background(Color.tile, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            }
    }
}

private struct ReadableContentWidth: ViewModifier {
    let maxWidth: CGFloat
    let minimumMargin: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, max(minimumMargin, (width - maxWidth) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// A list or form section header in the site's eyebrow style: monospace, tracked, uppercase, muted.
struct FolioHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .eyebrow()
            .foregroundStyle(Color.muted)
    }
}

/// The site's card folio: a number and a label on one line over a hairline ("01 · TODAY",
/// "YOUR RANK").
struct FolioRow: View {
    let leading: String
    let trailing: String
    var color: Color = .soft

    var body: some View {
        // Both when they fit; the number and Window alone when they don't (large text).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(leading)
                Spacer(minLength: 8)
                Text(trailing)
            }
            Text(leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .eyebrow()
        .foregroundStyle(color)
        .lineLimit(1)
        .padding(.bottom, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// The site's primary action: a lime slab with ink text ("Download for Mac").
struct LimeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .background(Color.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.lime.opacity(configuration.isPressed ? 0.1 : 0.28), radius: 18, y: 8)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// A secondary action on ink: a raised tile with white text.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 16)
            .background(Color.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.2 : 0.08), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - The square field, alive

/// The site's hero backdrop, drifting slowly. Still when Reduce Motion is on. Paused (holding its
/// last frame) when the app isn't active, in Low Power Mode, and after `idleAfter` seconds without
/// a touch anywhere in the app (`InteractionClock`); a touch starts it again. Its own view, so its
/// ticks never invalidate the list around it.
struct AnimatedSquareField: View {
    var light: UnitPoint = UnitPoint(x: 0.72, y: 0.3)
    var reach: Double = 0.55
    var cell: CGFloat = 18
    var tone: FieldTone
    var idleAfter: Duration = .seconds(10)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(InteractionClock.self) private var interactions: InteractionClock?
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var isIdle = false

    var body: some View {
        let paused = reduceMotion || scenePhase != .active || isLowPower || isIdle
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: paused)) { context in
            SquareFieldCanvas(
                light: light, reach: reach, cell: cell,
                // Reduce Motion: the still field. Otherwise a pause keeps the frame it stopped on.
                time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600),
                tone: tone
            )
        }
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .task(id: interactions?.lastTouch) {
            isIdle = false
            try? await Task.sleep(for: idleAfter)
            if !Task.isCancelled { isIdle = true }
        }
    }
}

/// When someone last touched the app, so ambient motion can rest when nobody's looking. A window
/// gesture recognizer records touches without taking part in them.
@MainActor @Observable
final class InteractionClock {
    private(set) var lastTouch = Date.now

    fileprivate func touched() { lastTouch = .now }

    /// Install once on the app's window (from a view inside it).
    func observe(_ window: UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchObserver }) else { return }
        window.addGestureRecognizer(TouchObserver(clock: self))
    }

    /// Sees every touch that begins, then fails at once, so it never cancels, delays, or claims
    /// a touch from the views underneath.
    private final class TouchObserver: UIGestureRecognizer {
        weak var clock: InteractionClock?

        init(clock: InteractionClock) {
            self.clock = clock
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            clock?.touched()
            state = .failed
        }

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}

/// Puts the `InteractionClock`'s observer on the window this view lands in.
struct InteractionClockInstaller: UIViewRepresentable {
    let clock: InteractionClock

    func makeUIView(context: Context) -> InstallerView { InstallerView(clock: clock) }
    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        let clock: InteractionClock
        init(clock: InteractionClock) {
            self.clock = clock
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { clock.observe(window) }
        }
    }
}

// MARK: - Rank-up burst

/// When your rank improves, contribution squares burst out of the number, as the menu-bar item
/// does on the site. Nothing plays with Reduce Motion on.
struct RankBurst: View {
    /// Changes to fire a burst.
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pieces: [(angle: Double, distance: CGFloat, size: CGFloat, level: Int)] = (0..<14).map { i in
        let angle = Double(i) / 14 * 2 * .pi + (i.isMultiple(of: 2) ? 0.2 : -0.15)
        return (angle, CGFloat(46 + (i * 37) % 44), CGFloat(6 + (i * 5) % 7), [4, 3, 4, 2, 3, 4][i % 6])
    }

    var body: some View {
        ZStack {
            ForEach(Self.pieces.indices, id: \.self) { index in
                let piece = Self.pieces[index]
                ContributionSquare(level: piece.level, size: piece.size)
                    .shadow(color: Color.lime.opacity(0.5), radius: 6)
                    .keyframeAnimator(initialValue: BurstFrame(), trigger: trigger) { content, frame in
                        content
                            .offset(x: cos(piece.angle) * piece.distance * frame.travel,
                                    y: sin(piece.angle) * piece.distance * frame.travel + 30 * frame.travel * frame.travel)
                            .scaleEffect(frame.scale)
                            .rotationEffect(.degrees(Double(index * 40) * frame.travel))
                            .opacity(frame.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.travel) {
                            LinearKeyframe(0, duration: 0.01)
                            SpringKeyframe(1, duration: 1.1, spring: .smooth(duration: 1.1))
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.05)
                            LinearKeyframe(1, duration: 0.6)
                            LinearKeyframe(0, duration: 0.5)
                        }
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(0.2, duration: 0.01)
                            SpringKeyframe(1, duration: 0.3)
                            LinearKeyframe(0.6, duration: 0.8)
                        }
                    }
            }
        }
        .opacity(reduceMotion || trigger == 0 ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct BurstFrame {
        var travel: CGFloat = 0
        var opacity: Double = 0
        var scale: CGFloat = 0.2
    }
}

// MARK: - System chrome

/// Restyles the system containers the app keeps (navigation bars, segmented controls) through
/// their appearance APIs: Inter Tight titles and lime selection. The bars themselves, their
/// placement, and their materials stay the system's, so they still move to the iPhone Duo's
/// vertical side bar.
enum SystemChrome {
    @MainActor static func apply() {
        let largeTitle = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: UIFont(name: CommittedType.displayFace, size: 34) ?? .preferredFont(forTextStyle: .largeTitle))
        // Inline titles stay San Francisco semibold: Inter Tight ExtraBold at 17 pt reads cramped.
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = [.font: largeTitle, .kern: -1.2, .foregroundColor: UIColor.white]
        navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]


        // In content (People's filter), the selected segment is a lime slab with ink text.
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(Color.lime)
        // Colors only: a font set here is fixed at launch and stops matching the control's text size.
        segmented.setTitleTextAttributes([.foregroundColor: UIColor(Color.ink)], for: .selected)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        // In a bar (the Board's Window switch) the system draws a glass segment and ignores the
        // tint, so the selection reads as lime text instead of ink text on nothing.
        let inBar = UISegmentedControl.appearance(whenContainedInInstancesOf: [UINavigationBar.self])
        inBar.setTitleTextAttributes([.foregroundColor: UIColor(Color.lime)], for: .selected)
        inBar.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
    }
}


// MARK: - The app's mark

/// The app icon as a tile: the lime trophy on a black squircle, as on the site.
struct AppMark: View {
    var size: CGFloat = 60
    /// The lime glow under the tile. Off inside a list row, where it reads as a box.
    var glows = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.11), Color(white: 0.03)], startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .overlay {
                TrophyMark(size: size * 0.62)
                    .shadow(color: Color.lime.opacity(0.45), radius: size * 0.16)
            }
            .frame(width: size, height: size)
            .shadow(color: Color.lime.opacity(glows ? 0.2 : 0), radius: size * 0.3, y: size * 0.12)
            .accessibilityHidden(true)
    }
}
