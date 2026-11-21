import SwiftUI
#if os(iOS)
import UIKit
#endif

// Share the board as an image: one of Committed's widgets, drawn by the widget's own views
// (`CommittedWidgetViews.swift`), on a square for a feed or a 9:16 story with a headline. It shows
// the Board's current Window and only the people the board shows, as the widgets do.

/// Which widget the image shows.
enum BoardShareStyle: String, CaseIterable, Identifiable, Sendable {
    /// The large widget: the top six, then you below a rule when you're further down.
    case board
    /// The medium widget: the person above you, you, and the person below.
    case race
    /// A compact share card with your rank and contribution count.
    case rank
    /// The small Committed Board widget: the leaders, or the top two and your race.
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: "Board"
        case .race: "Your race"
        case .rank: "Rank"
        case .list: "Top 4"
        }
    }

    /// The widget's size in points on the biggest iPhones, where its layout has the most room.
    /// The board grows past the Home Screen's height to fit its rows (`rows`, counting you), with no
    /// empty space under them.
    func widgetSize(rows: Int, dividesSelf: Bool) -> CGSize {
        switch self {
        case .board:
            // Header and margins, then each row at its height plus the 8 pt between rows, and the
            // rule over your row when you're further down. Measured from renders at the fixed
            // Dynamic Type size the card uses.
            let height = 56 + CGFloat(rows) * 38.2 - 8 + (dividesSelf ? 13 : 0)
            return CGSize(width: 364, height: max(height, 170))
        case .race: return CGSize(width: 364, height: 170)
        case .rank, .list: return CGSize(width: 170, height: 170)
        }
    }
}

/// The image's shape.
enum BoardShareFormat: String, CaseIterable, Identifiable, Sendable {
    /// 1080 × 1080, for a feed post or a message.
    case square
    /// 1080 × 1920, for Instagram and other stories.
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: "Square"
        case .story: "Story"
        }
    }

    /// The layout size in points; it renders at `renderScale`.
    var canvas: CGSize {
        switch self {
        case .square: CGSize(width: 540, height: 540)
        case .story: CGSize(width: 540, height: 960)
        }
    }

    static let renderScale: CGFloat = 2

    var pixelSize: CGSize {
        CGSize(width: canvas.width * Self.renderScale, height: canvas.height * Self.renderScale)
    }

    /// The most room the widget may take, in points, before it's scaled to fit.
    fileprivate var widgetRoom: CGSize {
        switch self {
        case .square: CGSize(width: 460, height: 380)
        case .story: CGSize(width: 476, height: 540)
        }
    }

    /// How many people the Board style shows, counting you: the large widget's six would leave a
    /// share image half empty.
    var boardRows: Int {
        switch self {
        case .square: 8
        case .story: 10
        }
    }

    /// The most rows any format shows: how many the board snapshot for sharing carries.
    static let maxBoardRows = allCases.map(\.boardRows).max() ?? WidgetSnapshot.topCount
}

/// The share image: a widget on the board's squares, with Committed's name under it, and on a story
/// a headline over it ("Who shipped more today?").
struct BoardShareCard: View {
    let snapshot: WidgetSnapshot
    let style: BoardShareStyle
    let format: BoardShareFormat
    var avatarCache: AvatarCache? = .shared

    var body: some View {
        let canvas = format.canvas
        ZStack {
            Color.ink
            BoardShareSquareField(brightness: format == .story ? 1 : 0.55)
            if format == .story {
                // The squares fade out behind the headline, so it reads.
                LinearGradient(colors: [Color.ink.opacity(0.94), Color.ink.opacity(0.8), Color.ink.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 440)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            // The squares fade out under the timestamp and the footer, so they read.
            LinearGradient(colors: [Color.ink.opacity(0), Color.ink.opacity(0.85), Color.ink.opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: format == .story ? 300 : 170)
                .frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: 0) {
                if format == .story {
                    BoardShareHeadline(window: snapshot.state.contributionWindow ?? .daily)
                        .padding(.top, 104)
                    Spacer(minLength: 24)
                } else {
                    Spacer(minLength: 0)
                }
                BoardShareWidget(snapshot: snapshot, style: style, format: format)
                BoardShareTimestamp(date: snapshot.state.updatedDate)
                    .padding(.top, 14)
                Spacer(minLength: 0)
                BoardShareFooter(peopleCount: snapshot.state.competitorCount)
                    .padding(.bottom, format == .story ? 72 : 26)
            }
            .padding(.horizontal, 32)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
        // An image looks the same whatever the phone's settings: dark, default text size, saved
        // avatars only (a renderer can't wait for network images), and never stale.
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.avatarFallbackStyle, .committed)
        .environment(\.loadsGitHubAvatars, false)
        // The Sample board's made-up people: initials, never a saved real avatar.
        .environment(\.savedAvatars, snapshot.isSampleBoard == true ? nil : avatarCache)
        .environment(\.liveRankIsStale, false)
    }

    /// The story's headline as text.
    static func headline(_ window: ContributionWindow) -> String {
        "Who shipped more \(BoardShareHeadline.when(window))"
    }

    /// When the numbers are from, as the image prints it ("As of Nov 8, 2026, 3:42 PM").
    static func timestamp(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day().year().hour().minute()
        style.locale = locale
        style.timeZone = timeZone
        return "As of \(date.formatted(style))"
    }
}

/// The widget itself, at its own size and in its own frame, scaled up to fill the format's room.
private struct BoardShareWidget: View {
    let snapshot: WidgetSnapshot
    let style: BoardShareStyle
    let format: BoardShareFormat

    var body: some View {
        let shown = style == .board ? snapshot.sharing(rows: format.boardRows) : snapshot
        let size = style.widgetSize(rows: shown.top.count + (shown.selfIsInTop ? 0 : 1),
                                    dividesSelf: !shown.selfIsInTop && shown.selfRow != nil)
        let room = format.widgetRoom
        let scale = min(room.width / size.width, room.height / size.height)
        content(shown)
            // A still image can't count up: the timestamp under the widget says when instead.
            .environment(\.showsUpdateAge, false)
            // The system's widget content margin, which the rows bleed into.
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(Color.ink, in: .rect(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }

    @ViewBuilder private func content(_ snapshot: WidgetSnapshot) -> some View {
        switch style {
        case .board: CommittedWidgetLarge(snapshot: snapshot)
        case .race: CommittedWidgetMedium(snapshot: snapshot)
        case .rank: BoardShareRank(state: snapshot.state)
        case .list: CommittedWidgetBoardSmall(snapshot: snapshot)
        }
    }
}

/// The compact export centers the rank and its heading independently of the trophy and count.
private struct BoardShareRank: View {
    let state: LiveRankState

    var body: some View {
        let ranked = state.rank != nil || state.competitorCount > 1
        let count = state.contributions.map { "\($0)" } ?? "–"
        let unit = state.contributions == 1 ? "Contribution" : "Contributions"
        VStack(alignment: .leading, spacing: 0) {
            Text(ranked ? heading : unit)
                .font(CommittedType.display(10, relativeTo: .caption))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text(ranked ? state.rank.map { "#\($0)" } ?? "–" : count)
                .font(CommittedType.display(54, relativeTo: .largeTitle))
                .displayTracking(54)
                .foregroundStyle(ranked ? Color.white : .lime)
                .accessibilityLabel(ranked ? LiveRankText.rankAccessibility(state) : LiveRankText.countAccessibility(state))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            TrophyMark(size: 36)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 3) {
                if ranked {
                    HStack(spacing: 6) {
                        ContributionGrid(size: 12, color: (state.contributions ?? 0) > 0 ? .lime : .muted)
                        Text("\(count) \(unit)")
                            .font(CommittedType.numeral(12, relativeTo: .caption))
                            .foregroundStyle(Color.lime)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(LiveRankText.countAccessibility(state))
                }
                if let status = state.emptyStateLine {
                    Text(status)
                        .font(CommittedType.numeral(10, relativeTo: .caption))
                        .foregroundStyle(Color.soft)
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, 6)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var heading: String {
        switch state.contributionWindow ?? .daily {
        case .daily: "Today’s Rank"
        case .weekly: "This Week’s Rank"
        case .monthly: "Last 30 Days Rank"
        }
    }
}

/// "Who shipped more today?", the site's headline, with the Window in lime.
private struct BoardShareHeadline: View {
    let window: ContributionWindow

    var body: some View {
        // The Window on its own line, so the headline never breaks mid-phrase.
        Text("Who shipped more\n\(Text(Self.when(window)).foregroundStyle(Color.lime))")
            .font(CommittedType.display(54, relativeTo: .largeTitle))
            .displayTracking(54)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(-4)
            .frame(maxWidth: .infinity)
    }

    static func when(_ window: ContributionWindow) -> String {
        switch window {
        case .daily: "today?"
        case .weekly: "this week?"
        case .monthly: "in 30 days?"
        }
    }
}

/// When the numbers are from, under the widget, so an old screenshot reads as old.
private struct BoardShareTimestamp: View {
    let date: Date

    var body: some View {
        Text(BoardShareCard.timestamp(date))
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Color.muted)
            .lineLimit(1)
    }
}

extension WidgetSnapshot {
    /// The board cut to `rows` people counting you: the leaders when you're among them, otherwise
    /// one fewer leader, and the large widget adds you below its rule.
    func sharing(rows: Int) -> WidgetSnapshot {
        var copy = self
        let leaders = Array(top.prefix(rows))
        copy.top = leaders.contains(where: \.isSelf) || selfRow == nil ? leaders : Array(top.prefix(max(rows - 1, 0)))
        return copy
    }
}

/// Committed and how many people are on the board, then where to get it.
struct BoardShareFooter: View {
    let peopleCount: Int

    var body: some View {
        HStack(spacing: 8) {
            TrophyMark(size: 18)
            Text(peopleCount > 1 ? "Committed · \(peopleCount) people" : "Committed")
            Spacer(minLength: 12)
            Text("gitcommitted.app").foregroundStyle(Color.muted)
        }
        .font(.system(size: 15, weight: .medium, design: .monospaced))
        .tracking(1)
        .textCase(.uppercase)
        .foregroundStyle(Color.soft)
        .lineLimit(1)
    }
}

/// The contribution graph's squares behind everything, as on the site: mostly empty, some green,
/// the odd lime one. The same pattern every time, brightest at the edges. Challenge's story image
/// draws it too.
struct BoardShareSquareField: View {
    let brightness: Double

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 16
            let pitch: CGFloat = 21
            let columns = Int(size.width / pitch) + 1
            let rows = Int(size.height / pitch) + 1
            let origin = CGPoint(x: (size.width - CGFloat(columns) * pitch + (pitch - cell)) / 2,
                                 y: (size.height - CGFloat(rows) * pitch + (pitch - cell)) / 2)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = hypot(size.width, size.height) / 2
            for row in 0..<rows {
                for column in 0..<columns {
                    let rect = CGRect(x: origin.x + CGFloat(column) * pitch, y: origin.y + CGFloat(row) * pitch,
                                      width: cell, height: cell)
                    let distance = hypot(rect.midX - center.x, rect.midY - center.y) / reach
                    let opacity = brightness * (0.25 + 0.75 * distance)
                    let color = Color.contributionSquares[Self.level(column: column, row: row)]
                    context.fill(Path(roundedRect: rect, cornerRadius: 3.5), with: .color(color.opacity(opacity)))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 0 (empty) to 4 (lime), from the square's position.
    static func level(column: Int, row: Int) -> Int {
        var hash = UInt32(truncatingIfNeeded: column &* 73_856_093) ^ UInt32(truncatingIfNeeded: row &* 19_349_663)
        hash ^= hash >> 13
        hash = hash &* 0x5bd1_e995
        hash ^= hash >> 15
        switch hash % 100 {
        case ..<58: return 0
        case ..<76: return 1
        case ..<89: return 2
        case ..<97: return 3
        default: return 4
        }
    }
}

// MARK: - Rendering

@MainActor
enum BoardShareRenderer {
    #if os(iOS)
    /// The image at `format.pixelSize`.
    static func image(_ snapshot: WidgetSnapshot, style: BoardShareStyle, format: BoardShareFormat) -> UIImage? {
        ShareImageRenderer.image(BoardShareCard(snapshot: snapshot, style: style, format: format))
    }

    #endif

    /// The image as a PNG in a temporary folder, named for what it shows, for the share sheet. Each
    /// render replaces the last one of the same style and format.
    static func file(
        _ snapshot: WidgetSnapshot,
        style: BoardShareStyle,
        format: BoardShareFormat,
        avatarCache: AvatarCache? = .shared
    ) throws -> URL {
        let window = (snapshot.state.contributionWindow ?? .daily).shortTitle.replacingOccurrences(of: " ", with: "-")
        let card = BoardShareCard(snapshot: snapshot, style: style, format: format, avatarCache: avatarCache)
        return try ShareImageRenderer.file(card, folder: "board-share",
                                           name: "Committed-\(window)-\(style.rawValue)-\(format.rawValue).png")
    }
}

/// The card scaled to fit its preview.
struct BoardSharePreview: View {
    let snapshot: WidgetSnapshot
    let style: BoardShareStyle
    let format: BoardShareFormat
    var avatarCache: AvatarCache? = .shared

    var body: some View {
        GeometryReader { proxy in
            let canvas = format.canvas
            let scale = min(proxy.size.width / canvas.width, proxy.size.height / canvas.height)
            BoardShareCard(snapshot: snapshot, style: style, format: format, avatarCache: avatarCache)
                .scaleEffect(scale)
                .frame(width: canvas.width * scale, height: canvas.height * scale)
                .clipShape(.rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.hairline, lineWidth: 1) }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.title), \(format.title.lowercased()) image")
    }
}
