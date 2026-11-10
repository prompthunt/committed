import Foundation
import WidgetKit

/// Keeps the Home Screen and Lock Screen widgets in step with the board. After each refresh (and
/// on a visibility change or Disconnect) it writes `WidgetSnapshot` to the App Group, then asks
/// WidgetKit to reload, but only when the snapshot changed: reloads come out of a daily budget.
@MainActor
final class WidgetPublisher {
    private let save: @MainActor (WidgetSnapshot?) -> Void
    private let reload: @MainActor () -> Void
    private var last: WidgetSnapshot??

    /// The defaults write to the App Group and reload through `WidgetCenter`; tests pass their own.
    init(
        save: @escaping @MainActor (WidgetSnapshot?) -> Void = WidgetPublisher.saveToAppGroup,
        reload: @escaping @MainActor () -> Void = {
            for kind in WidgetSnapshot.kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        }
    ) {
        self.save = save
        self.reload = reload
    }

    /// Publish a snapshot, or nil when disconnected. A repeat of the last one does nothing.
    func publish(_ snapshot: WidgetSnapshot?) {
        guard last != .some(snapshot) else { return }
        last = .some(snapshot)
        save(snapshot)
        reload()
    }

    nonisolated static func saveToAppGroup(_ snapshot: WidgetSnapshot?) {
        if let snapshot {
            try? snapshot.save()
        } else {
            WidgetSnapshot.remove()
        }
    }
}

// MARK: - Board

// App only: the extension can't rank, so it never builds a snapshot.
extension WidgetSnapshot {
    /// The snapshot for the visible board, ranked as the Board ranks it, with the first `rows`
    /// people (the large widget's six; the share images take more).
    @MainActor
    static func board(
        _ store: StandingsStore,
        window: ContributionWindow,
        rankDelta: (String) -> Int?,
        now: Date,
        rows: Int = topCount
    ) -> WidgetSnapshot? {
        guard let me = store.selfCompetitor?.username else { return nil }
        let state = LiveRankState.board(store, window: window, rankDelta: rankDelta, now: now)
        let competitors = store.visibleCompetitors
        let visible = Set(competitors.map(\.username))
        let standings = store.standings(for: window).filter { login, standing in
            visible.contains(login) && standing.lastUpdated != .distantPast
        }
        let ranked = Ranking.order(competitors: competitors, standings: standings, window: window)
        let board = ranked.map { entry in
            let login = entry.competitor.username
            let standing = standings[login]
            return Row(
                rank: entry.rank,
                login: login,
                contributions: standing?.window == window ? standing?.contributions : nil,
                movement: window == .daily ? rankDelta(login) ?? 0 : 0,
                isSelf: entry.competitor.isSelf
            )
        }
        return WidgetSnapshot(selfLogin: me, state: state, top: Array(board.prefix(rows)),
                              people: competitors.map(\.username), board: board)
    }
}
