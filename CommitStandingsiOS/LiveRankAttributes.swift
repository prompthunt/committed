import ActivityKit
import Foundation

/// Live rank's Live Activity. The type name and its single static attribute are part of the
/// relay contract (push-to-start sends `"attributes-type": "LiveRankAttributes"` with
/// `{"selfLogin": …}`), so don't rename either. The changing part is the shared `LiveRankState`.
struct LiveRankAttributes: ActivityAttributes {
    typealias ContentState = LiveRankState
    typealias Neighbor = LiveRankState.Neighbor

    var selfLogin: String
}
