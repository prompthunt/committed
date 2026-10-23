import Foundation

/// A relative position change between two standings snapshots: a rival who crossed the signed-in
/// user in the rankings since the previous refresh.
struct RankChangeEvent: Equatable {
    enum Direction: Equatable {
        case rivalPassedMe   // was below me, now above me
        case iPassedRival    // was above me, now below me
    }
    let rivalUsername: String
    let direction: Direction
    /// Current-snapshot contribution counts (what to show in the notification).
    let rivalContributions: Int
    let myContributions: Int
}

/// Pure detection of relative rank crossings. Compares contribution counts *relative to the
/// signed-in user* rather than integer ranks, so there's no dependency on the board's index-based
/// tie-breaking.
///
/// A crossing is "was at-or-below me, now strictly above me" (rival passed me) or "was at-or-above
/// me, now strictly below me" (I passed them). Requiring a *strict* end state means a sustained
/// tie, or a rival merely catching up to an exact tie, fires nothing — but a genuine pass that
/// happens to go through a tie still registers once. The two directions are mutually exclusive
/// because they disagree on the current comparison.
enum RankChangeDetector {
    /// - Parameters:
    ///   - previous: the prior snapshot (username → contributions), or nil on the first refresh.
    ///   - current: the latest snapshot (username → contributions).
    ///   - selfUsername: the signed-in user's username.
    /// - Returns: one event per rival that crossed self, ordered by username for determinism.
    ///   Empty when there's no previous snapshot, self is missing from either snapshot, or nothing
    ///   crossed. Rivals not present in *both* snapshots are ignored.
    static func crossings(
        previous: [String: Int]?,
        current: [String: Int],
        selfUsername: String
    ) -> [RankChangeEvent] {
        guard let previous,
              let mePrev = previous[selfUsername],
              let meNow = current[selfUsername] else { return [] }

        var events: [RankChangeEvent] = []
        for (rival, rivalNow) in current where rival != selfUsername {
            guard let rivalPrev = previous[rival] else { continue }  // only rivals in both snapshots
            if rivalPrev <= mePrev && rivalNow > meNow {
                events.append(RankChangeEvent(
                    rivalUsername: rival, direction: .rivalPassedMe,
                    rivalContributions: rivalNow, myContributions: meNow))
            } else if rivalPrev >= mePrev && rivalNow < meNow {
                events.append(RankChangeEvent(
                    rivalUsername: rival, direction: .iPassedRival,
                    rivalContributions: rivalNow, myContributions: meNow))
            }
        }
        return events.sorted { $0.rivalUsername < $1.rivalUsername }
    }
}
