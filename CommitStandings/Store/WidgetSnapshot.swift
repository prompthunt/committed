import Foundation

/// What Committed's Home Screen and Lock Screen widgets show: Live rank's state for its Window and
/// the top of the board. The iPhone app writes it to the App Group after every refresh
/// (`WidgetPublisher`); the widget extension only reads it, since it can't fetch or rank anything.
/// Missing means not connected: the widgets then ask you to open Committed.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// One board row, ranked by `Ranking.order`.
    struct Row: Codable, Equatable, Sendable {
        var rank: Int
        var login: String
        /// nil while their count hasn't loaded: the row shows a placeholder, never zero.
        var contributions: Int?
        /// Places moved today (+ up, − down). 0 outside Today.
        var movement: Int
        var isSelf: Bool
    }

    /// Your GitHub login.
    var selfLogin: String
    /// The Live rank state for the widgets' Window (Live rank's Window setting).
    var state: LiveRankState
    /// The leaders, in board order, at most `topCount`. You're in it only if you place there.
    var top: [Row]

    /// Rows the large widget has room for.
    static let topCount = 6

    /// The widgets' kinds: the app reloads them, the extension declares them. The rank card
    /// (every size), and the small Board list made for StandBy.
    static let widgetKind = "CommittedBoard"
    static let boardListKind = "CommittedBoardList"
    static let kinds = [widgetKind, boardListKind]

    /// Your row, when your count has loaded.
    var selfRow: Row? {
        guard let rank = state.rank, let contributions = state.contributions else { return nil }
        return Row(rank: rank, login: selfLogin, contributions: contributions,
                   movement: state.movementToday, isSelf: true)
    }

    /// Whether you're among `top`.
    var selfIsInTop: Bool { top.contains(where: \.isSelf) }

    /// The board in `count` rows, for the small Board widget (StandBy shows only small widgets):
    /// the leaders when you're among them, otherwise the first few, the person just ahead of you,
    /// and you, so your race is always on screen.
    func boardRows(count: Int = 4) -> [Row] {
        guard count > 0 else { return [] }
        let leaders = Array(top.prefix(count))
        guard let me = selfRow, !leaders.contains(where: \.isSelf) else { return leaders }
        var rows = Array(top.prefix(max(count - 2, 0)))
        if let above = state.above, me.rank - 1 > (rows.last?.rank ?? 0) {
            rows.append(Row(rank: me.rank - 1, login: above.login, contributions: above.contributions,
                            movement: above.movementToday, isSelf: false))
        } else if rows.count < count - 1, let next = top.dropFirst(rows.count).first {
            rows.append(next)
        }
        rows.append(me)
        return rows
    }
}

// MARK: - Storage

extension WidgetSnapshot {
    /// `widget-snapshot.json` in the App Group, beside the avatar cache.
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AvatarCache.appGroup)?
            .appendingPathComponent("widget-snapshot.json")
    }

    /// The last snapshot the app wrote, or nil when there's none (or it can't be read).
    static func load(from url: URL? = fileURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(to url: URL? = Self.fileURL) throws {
        guard let url else { return }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func remove(at url: URL? = fileURL) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Placeholder

extension WidgetSnapshot {
    /// The widget gallery and the redacted placeholder. A fresh install shows this shape, never an
    /// empty box.
    static func sample(now: Date = Date()) -> WidgetSnapshot {
        let updatedAt = Int(now.timeIntervalSince1970)
        return WidgetSnapshot(
            selfLogin: "you",
            state: LiveRankState(
                window: ContributionWindow.daily.rawValue, rank: 3, competitorCount: 8, contributions: 12,
                above: .init(login: "alex", contributions: 15, movementToday: 1),
                below: .init(login: "sam-rivera", contributions: 9, movementToday: -1),
                movementToday: 1, updatedAt: updatedAt
            ),
            top: [
                Row(rank: 1, login: "jordan", contributions: 21, movement: 0, isSelf: false),
                Row(rank: 2, login: "alex", contributions: 15, movement: 1, isSelf: false),
                Row(rank: 3, login: "you", contributions: 12, movement: 1, isSelf: true),
                Row(rank: 4, login: "sam-rivera", contributions: 9, movement: -1, isSelf: false),
                Row(rank: 5, login: "riley", contributions: 6, movement: 0, isSelf: false),
                Row(rank: 6, login: "casey", contributions: 4, movement: -1, isSelf: false),
            ]
        )
    }
}
