import SwiftUI
import UIKit

// Share the board as an image: one of Committed's widgets, drawn by the widget's own views
// (`CommittedWidgetViews.swift`), on a square for a feed or a 9:16 story with a headline. It shows
// the Board's current Window and only the people the board shows, as the widgets do. On the 1st it
// also offers last month's Final standings: the large widget's rows with medals, under "October final".

/// Which widget the image shows. Not `CaseIterable`: Final standings is offered only with a
/// finished month (`BoardShareRequest.styles`), so nothing should list every style.
enum BoardShareStyle: String, Identifiable, Sendable {
    /// The large widget: the top six, then you below a rule when you're further down.
    case board
    /// The medium widget: the person above you, you, and the person below.
    case race
    /// The small widget: your rank big, your count, and the gap to pass.
    case rank
    /// The small Committed Board widget: the leaders, or the top two and your race.
    case list
    /// A finished month's Final standings: the large widget's rows with medals on the top three,
    /// headed "October final".
    case final

    /// The live board's styles, in the carousel's order.
    static let live: [BoardShareStyle] = [.board, .race, .rank, .list]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: "Board"
        case .race: "Your race"
        case .rank: "Rank"
        case .list: "Top 4"
        case .final: "Final standings"
        }
    }

    /// The widget's size in points on the biggest iPhones, where its layout has the most room.
    /// The board grows past the Home Screen's height to fit its rows (`rows`, counting you), with no
    /// empty space under them.
    func widgetSize(rows: Int, dividesSelf: Bool) -> CGSize {
        switch self {
        case .board, .final:
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
/// a headline over it ("Who shipped more today?", or "…in October?" for Final standings).
struct BoardShareCard: View {
    let snapshot: WidgetSnapshot
    let style: BoardShareStyle
    let format: BoardShareFormat
    /// The finished month, for Final standings; nil for the live board.
    private let month: CalendarMonth?

    /// The live board in one of its styles.
    init(snapshot: WidgetSnapshot, style: BoardShareStyle, format: BoardShareFormat) {
        self.snapshot = snapshot
        self.style = style
        self.format = format
        month = nil
    }

    /// A finished month's Final standings.
    init(finals: FinalStandingsShare, format: BoardShareFormat) {
        snapshot = finals.snapshot
        style = .final
        self.format = format
        month = finals.month
    }

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
                    BoardShareHeadline(when: month.map { "in \($0.name)?" }
                                       ?? BoardShareHeadline.when(snapshot.state.contributionWindow ?? .daily))
                        .padding(.top, 104)
                    Spacer(minLength: 24)
                } else {
                    Spacer(minLength: 0)
                }
                BoardShareWidget(snapshot: snapshot, style: style, format: format,
                                 title: month.map { "\($0.name) final" })
                BoardShareTimestamp(text: month.map(Self.finalLine) ?? Self.timestamp(snapshot.state.updatedDate))
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
        .environment(\.savedAvatars, snapshot.savedAvatars)
        .environment(\.liveRankIsStale, false)
    }

    /// The story's headline as text.
    static func headline(_ window: ContributionWindow) -> String {
        "Who shipped more \(BoardShareHeadline.when(window))"
    }

    /// A finished month's story headline: "Who shipped more in October?".
    static func headline(_ month: CalendarMonth) -> String {
        "Who shipped more in \(month.name)?"
    }

    /// Under a finished month's widget, in place of the timestamp: its numbers are final, not "as
    /// of" a moment. "Final · October 2026".
    static func finalLine(_ month: CalendarMonth) -> String {
        "Final · \(month.name) \(month.year)"
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
    /// The large widget's header in place of the Window ("October final").
    var title: String? = nil

    var body: some View {
        let shown = style == .board || style == .final ? snapshot.sharing(rows: format.boardRows) : snapshot
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
        case .rank: CommittedWidgetSmall(snapshot: snapshot)
        case .list: CommittedWidgetBoardSmall(snapshot: snapshot)
        case .final: CommittedWidgetLarge(snapshot: snapshot, title: title)
        }
    }
}

/// "Who shipped more today?", the site's headline, with the Window (or the month) in lime.
private struct BoardShareHeadline: View {
    let when: String

    var body: some View {
        // The Window on its own line, so the headline never breaks mid-phrase.
        Text("Who shipped more\n\(Text(when).foregroundStyle(Color.lime))")
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
        case .month: "this month?"
        }
    }
}

/// When the numbers are from, under the widget, so an old screenshot reads as old.
private struct BoardShareTimestamp: View {
    let text: String

    var body: some View {
        Text(text)
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
private struct BoardShareFooter: View {
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
/// the odd lime one. The same pattern every time, brightest at the edges.
private struct BoardShareSquareField: View {
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
    /// The image at `format.pixelSize`.
    static func image(_ snapshot: WidgetSnapshot, style: BoardShareStyle, format: BoardShareFormat) -> UIImage? {
        image(BoardShareCard(snapshot: snapshot, style: style, format: format))
    }

    /// A finished month's Final standings at `format.pixelSize`.
    static func image(_ finals: FinalStandingsShare, format: BoardShareFormat) -> UIImage? {
        image(BoardShareCard(finals: finals, format: format))
    }

    static func image(_ card: BoardShareCard) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = BoardShareFormat.renderScale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// The image as a PNG in a temporary folder, named for what it shows, for the share sheet. Each
    /// render replaces the last one of the same style and format.
    static func file(_ snapshot: WidgetSnapshot, style: BoardShareStyle, format: BoardShareFormat) throws -> URL {
        let window = (snapshot.state.contributionWindow ?? .daily).shortTitle.replacingOccurrences(of: " ", with: "-")
        return try file(BoardShareCard(snapshot: snapshot, style: style, format: format),
                        named: "Committed-\(window)-\(style.rawValue)-\(format.rawValue).png")
    }

    /// A finished month's Final standings as a PNG: `Committed-October-final-square.png`.
    static func file(_ finals: FinalStandingsShare, format: BoardShareFormat) throws -> URL {
        try file(BoardShareCard(finals: finals, format: format),
                 named: "Committed-\(finals.month.name)-final-\(format.rawValue).png")
    }

    private static func file(_ card: BoardShareCard, named name: String) throws -> URL {
        guard let data = image(card)?.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("board-share", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Final standings

/// A finished month's Final standings as Share board draws them: its rows as the large widget's,
/// with medals on the top three and no streaks or movement, under "October final".
struct FinalStandingsShare: Equatable, Sendable {
    let month: CalendarMonth
    /// The rows as a board snapshot, so the large widget and its share layout (`sharing(rows:)`, you
    /// below the rule when further down) draw them as they draw a live board.
    let snapshot: WidgetSnapshot

    /// The widget's header: "October final".
    var title: String { "\(month.name) final" }

    /// nil without you on the board. `isSampleBoard` keeps the Sample board's made-up people on
    /// initials.
    init?(_ finals: FinalStandings, isSampleBoard: Bool, now: Date) {
        guard let you = finals.you else { return nil }
        month = finals.month
        let rows = finals.entries.map { entry in
            WidgetSnapshot.Row(rank: entry.rank, login: entry.competitor.username, contributions: entry.contributions,
                               movement: 0, isSelf: entry.competitor.isSelf, medal: entry.medal)
        }
        var snapshot = WidgetSnapshot(
            selfLogin: you.competitor.username,
            state: LiveRankState(window: ContributionWindow.month.rawValue, rank: you.rank,
                                 competitorCount: finals.entries.count, contributions: you.contributions,
                                 above: nil, below: nil, movementToday: 0,
                                 updatedAt: Int(now.timeIntervalSince1970)),
            top: Array(rows.prefix(BoardShareFormat.maxBoardRows))
        )
        if isSampleBoard { snapshot.isSampleBoard = true }
        self.snapshot = snapshot
    }
}

// MARK: - Sheet

/// What Share board offers: the live board's styles, and a finished month's Final standings when
/// there is one (last month's on the 1st, or a past month from the person view). Frozen when Share
/// is tapped, so a refresh can't change the image under the carousel.
struct BoardShareRequest: Identifiable {
    let id = UUID()
    /// The live board; nil when only a finished month is shared.
    let snapshot: WidgetSnapshot?
    let finals: FinalStandingsShare?
    /// The page the carousel opens on.
    let initialStyle: BoardShareStyle

    /// The live board, with `finals` offered first when there are some; `opensOnFinals` (the Board
    /// showing them) opens the carousel there.
    init(snapshot: WidgetSnapshot, finals: FinalStandingsShare? = nil, opensOnFinals: Bool = false) {
        self.snapshot = snapshot
        self.finals = finals
        initialStyle = finals != nil && opensOnFinals ? .final : .board
    }

    /// A finished month's Final standings alone.
    init(finals: FinalStandingsShare) {
        snapshot = nil
        self.finals = finals
        initialStyle = .final
    }

    /// The carousel's pages: Final standings only when there's a finished month to show.
    var styles: [BoardShareStyle] {
        (finals == nil ? [] : [.final]) + (snapshot == nil ? [] : BoardShareStyle.live)
    }

    /// The image for `style` in `format`.
    func card(_ style: BoardShareStyle, format: BoardShareFormat) -> BoardShareCard? {
        if style == .final { return finals.map { BoardShareCard(finals: $0, format: format) } }
        return snapshot.map { BoardShareCard(snapshot: $0, style: style, format: format) }
    }

    /// The PNG for `style` in `format`, named for what it shows.
    @MainActor
    func file(_ style: BoardShareStyle, format: BoardShareFormat) throws -> URL {
        if style == .final, let finals { return try BoardShareRenderer.file(finals, format: format) }
        guard let snapshot else { throw CocoaError(.fileWriteUnknown) }
        return try BoardShareRenderer.file(snapshot, style: style, format: format)
    }
}

/// What the Share button opens: swipe between the widget styles, pick Square or Story, and share.
struct BoardShareSheet: View {
    let request: BoardShareRequest
    @State private var style: BoardShareStyle
    @State private var format: BoardShareFormat
    @State private var sharing: SharedFile?
    @Environment(\.dismiss) private var dismiss

    init(request: BoardShareRequest, initialFormat: BoardShareFormat = .square) {
        self.request = request
        _style = State(initialValue: request.initialStyle)
        _format = State(initialValue: initialFormat)
    }

    /// The live board's styles.
    init(snapshot: WidgetSnapshot, initialFormat: BoardShareFormat = .square) {
        self.init(request: BoardShareRequest(snapshot: snapshot), initialFormat: initialFormat)
    }

    /// A finished month's Final standings alone, as the person view's past months share them.
    init(finals: FinalStandingsShare, initialFormat: BoardShareFormat = .square) {
        self.init(request: BoardShareRequest(finals: finals), initialFormat: initialFormat)
    }

    private struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                TabView(selection: $style) {
                    ForEach(request.styles) { style in
                        if let card = request.card(style, format: format) {
                            BoardSharePreview(card: card)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 36)
                                .tag(style)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: request.styles.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))

                Text(style.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.soft)
                    .contentTransition(.opacity)

                Picker("Format", selection: $format) {
                    ForEach(BoardShareFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)

                Button {
                    sharing = (try? request.file(style, format: format)).map(SharedFile.init)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LimeButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .inkScreen()
            .navigationTitle("Share board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // The image alone: no title or caption rides along into the post or message.
        .sheet(item: $sharing) { file in
            BoardShareActivity(url: file.url)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }
}

/// The system share sheet with only the PNG.
private struct BoardShareActivity: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// One page of the carousel: the card itself, scaled to fit the page.
private struct BoardSharePreview: View {
    let card: BoardShareCard

    var body: some View {
        GeometryReader { proxy in
            let canvas = card.format.canvas
            let scale = min(proxy.size.width / canvas.width, proxy.size.height / canvas.height)
            card
                .scaleEffect(scale)
                .frame(width: canvas.width * scale, height: canvas.height * scale)
                .clipShape(.rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.hairline, lineWidth: 1) }
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.style.title), \(card.format.title.lowercased()) image")
    }
}
