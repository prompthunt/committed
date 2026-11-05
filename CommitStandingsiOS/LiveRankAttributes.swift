import ActivityKit
import Foundation

/// Live rank's Live Activity. The type name and `selfLogin` are part of the relay contract
/// (push-to-start sends `"attributes-type": "LiveRankAttributes"` with `{"selfLogin": …}`), so
/// don't rename either. The changing part is the shared `LiveRankState`.
struct LiveRankAttributes: ActivityAttributes {
    typealias ContentState = LiveRankState
    typealias Neighbor = LiveRankState.Neighbor

    var selfLogin: String
    /// Unix seconds the app started this activity, reported to the relay so it rotates the
    /// activity on time. Nil (absent) for one the relay started with push-to-start.
    var startedAt: Int?
}
