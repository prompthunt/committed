import Foundation

/// What Committed's Home Screen and Lock Screen widgets show: Live rank's state for its Window and
/// the top of the board. The iPhone app writes it to the App Group after every refresh
/// (`WidgetPublisher`), with everyone on the board, so the widget extension can refetch their
/// counts and re-rank on its own every 15 minutes (`WidgetRefresh`) and write the result back.
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
        /// Their current streak, shown from 2 days beside a loaded count (`StreakLabel`). nil
        /// without their calendar, and in snapshots from before streaks.
        var streak: Int? = nil
    }

    /// Your GitHub login.
    var selfLogin: String
    /// The Live rank state for the widgets' Window (Live rank's Window setting).
    var state: LiveRankState
    /// The leaders, in board order, at most `topCount`. You're in it only if you place there.
    var top: [Row]
    /// True for the Sample board. Its people are made up, so the widgets show initials for them,
    /// never an avatar saved for a real account with the same login. nil (left out) for a real
    /// board, so a snapshot from before this field reads as one.
    var isSampleBoard: Bool? = nil
    /// Everyone visible on the board, in board order (you first), which `Ranking.order` breaks
    /// ties by. What the widgets refetch. nil from a build before widget refresh: those snapshots
    /// show as written until the app saves a new one.
    var people: [String]? = nil
    /// Every visible person's row, ranked: the counts a refresh falls back on for anyone GitHub
    /// didn't answer for, and today's movement, which a refresh carries on from.
    var board: [Row]? = nil

    /// Rows the large widget has room for.
    static let topCount = 6

    /// How long after its data a widget looks stale (colors stepped down). Longer
    /// than Live rank's 20 minutes: widgets refresh every 15 minutes at best, and iOS's reload
    /// budget can stretch that.
    static let staleInterval: TimeInterval = 60 * 60

    /// When the widgets show these numbers as stale.
    var staleDate: Date { state.updatedDate.addingTimeInterval(Self.staleInterval) }

    /// The widgets' kinds: the app reloads them, the extension declares them. The rank card
    /// (every size), and the small Board list made for StandBy.
    static let widgetKind = "CommittedBoard"
    static let boardListKind = "CommittedBoardList"
    static let kinds = [widgetKind, boardListKind]

    /// Saved avatars for the widgets' rows: none on the Sample board (initials only).
    var savedAvatars: AvatarCache? { isSampleBoard == true ? nil : .shared }

    /// Your row, when your count has loaded.
    var selfRow: Row? {
        guard let rank = state.rank, let contributions = state.contributions else { return nil }
        return Row(rank: rank, login: selfLogin, contributions: contributions,
                   movement: state.movementToday, isSelf: true, streak: state.streak)
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
                            movement: above.movementToday, isSelf: false, streak: above.streak))
        } else if rows.count < count - 1, let next = top.dropFirst(rows.count).first {
            rows.append(next)
        }
        rows.append(me)
        return rows
    }
}

// MARK: - Refresh

extension WidgetSnapshot {
    /// The board re-ranked with new counts, as the app would rank it (`Ranking.order`, then
    /// `LiveRankState.derive`), dated `now`. Anyone missing from `counts` keeps their last count,
    /// except on Today after midnight, when yesterday's count would be wrong: they show no data.
    /// Today's movement carries on from the saved board (the day's baseline is the saved movement
    /// plus the saved rank) and starts again at 0 on a new day.
    ///
    /// `streaks` come from the calendars just fetched. Anyone missing from it keeps their saved
    /// streak the same day; after midnight it may have grown or broken, so they show none rather
    /// than a wrong one.
    func refreshed(counts: [String: Int], streaks: [String: Int] = [:], now: Date,
                   calendar: Calendar = .current) -> WidgetSnapshot {
        guard let people, let window = state.contributionWindow else { return self }
        let saved = Dictionary((board ?? top).map { ($0.login, $0) }, uniquingKeysWith: { first, _ in first })
        let sameDay = calendar.isDate(state.updatedDate, inSameDayAs: now)
        let keepsOldCounts = window != .daily || sameDay

        var standings: [String: Standing] = [:]
        for login in people {
            guard let count = counts[login] ?? (keepsOldCounts ? saved[login]?.contributions : nil) else { continue }
            standings[login] = Standing(username: login, contributions: count, window: window,
                                        lastUpdated: now, state: .loaded)
        }
        var streakOf: [String: Int] = [:]
        for login in people {
            if let streak = streaks[login] ?? (sameDay && counts[login] == nil ? saved[login]?.streak : nil) {
                streakOf[login] = streak
            }
        }
        let competitors = people.map { Competitor(username: $0, isSelf: $0 == selfLogin) }
        let ranked = Ranking.order(competitors: competitors, standings: standings, window: window)

        var deltas: [String: Int] = [:]
        if window == .daily, sameDay {
            for entry in ranked {
                let login = entry.competitor.username
                if let before = saved[login] { deltas[login] = before.movement + before.rank - entry.rank }
            }
        }
        let rows = ranked.map { entry in
            let login = entry.competitor.username
            return Row(rank: entry.rank, login: login, contributions: standings[login]?.contributions,
                       movement: deltas[login] ?? 0, isSelf: entry.competitor.isSelf, streak: streakOf[login])
        }
        var next = self
        next.state = LiveRankState.derive(competitors: competitors, standings: standings, window: window,
                                          rankDeltas: deltas, streaks: streakOf, now: now)
        next.top = Array(rows.prefix(Self.topCount))
        next.board = rows
        return next
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
    /// empty box. Its people are the Sample board's made-up GitHub logins (none is a real account),
    /// with `ari-linden` as you.
    static func sample(now: Date = Date()) -> WidgetSnapshot {
        let updatedAt = Int(now.timeIntervalSince1970)
        return WidgetSnapshot(
            selfLogin: "ari-linden",
            state: LiveRankState(
                window: ContributionWindow.daily.rawValue, rank: 3, competitorCount: 8, contributions: 12,
                above: .init(login: "odile-m", contributions: 15, movementToday: 1, streak: 6),
                below: .init(login: "ezra-q", contributions: 9, movementToday: -1, streak: 3),
                movementToday: 1, streak: 14, updatedAt: updatedAt
            ),
            top: [
                Row(rank: 1, login: "ines-volk", contributions: 21, movement: 0, isSelf: false, streak: 47),
                Row(rank: 2, login: "odile-m", contributions: 15, movement: 1, isSelf: false, streak: 6),
                Row(rank: 3, login: "ari-linden", contributions: 12, movement: 1, isSelf: true, streak: 14),
                Row(rank: 4, login: "ezra-q", contributions: 9, movement: -1, isSelf: false, streak: 3),
                Row(rank: 5, login: "bram-ott", contributions: 6, movement: 0, isSelf: false, streak: 0),
                Row(rank: 6, login: "niko-vane", contributions: 4, movement: -1, isSelf: false, streak: 1),
            ]
        )
    }
}
