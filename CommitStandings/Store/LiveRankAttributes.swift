import ActivityKit
import Foundation

/// Live rank's Live Activity type: iPhone app and Live rank extension only (ActivityKit isn't on
/// the Mac). The name and the single `selfLogin` attribute are part of the relay contract: its
/// push-to-start sends `attributes-type: "LiveRankAttributes"` and `attributes: {"selfLogin": …}`.
/// The content state is the shared `LiveRankState`.
struct LiveRankAttributes: ActivityAttributes {
    typealias ContentState = LiveRankState
    typealias Neighbor = LiveRankState.Neighbor

    /// Your GitHub login. A different account means a different activity.
    var selfLogin: String
}
