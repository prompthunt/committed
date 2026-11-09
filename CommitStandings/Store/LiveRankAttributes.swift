import ActivityKit
import Foundation

/// Live rank's Live Activity type: iPhone app and Live rank extension only (ActivityKit isn't on
/// the Mac). The name and the `selfLogin` attribute are part of the relay contract: its
/// push-to-start sends `attributes-type: "LiveRankAttributes"` and `attributes: {"selfLogin": …}`.
/// The content state is the shared `LiveRankState`.
struct LiveRankAttributes: ActivityAttributes {
    typealias ContentState = LiveRankState
    typealias Neighbor = LiveRankState.Neighbor

    /// Your GitHub login. A different account means a different activity.
    var selfLogin: String
    /// True on the Sample board, whose people are made up: Live rank shows initials for them, never
    /// an avatar saved for a real account with the same login. nil for a real board, including
    /// the relay's push-to-start, which sends only `selfLogin`.
    var isSampleBoard: Bool? = nil
}

extension LiveRankAttributes {
    /// Saved avatars for this activity's rows: none on the Sample board (initials only).
    var savedAvatars: AvatarCache? { isSampleBoard == true ? nil : .shared }
}
