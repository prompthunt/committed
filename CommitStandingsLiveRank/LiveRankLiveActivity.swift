import ActivityKit
import SwiftUI
import WidgetKit

/// Live rank: your place on the board in the Dynamic Island and on the Lock Screen.
///
/// The expanded island and the Lock Screen list the person above you, you, and the person below
/// in the board's own row (`LiveRankRows`); the row carries the rank, so there's no separate
/// headline. Over the rows sit the trophy and the Window ("Today") and, on the right, how long ago
/// the numbers were updated ("13 min, 36 sec"), counting up live between updates. Compact and
/// minimal show your rank and count.
///
/// Every presentation uses tabular numerals and no fixed widths, so it reads in the iPhone Duo's
/// vertical Dynamic Island as well as the standard horizontal one. A missing count shows a
/// placeholder, never zero, and an empty state says what it's waiting for. Once the content passes
/// its stale date (20 minutes after the data), colors step down (lime to deep lime, white to soft)
/// rather than fading, the Lock Screen's field goes dark, and compact's count
/// gets a clock, since it has no room for the age. Tapping opens the Board on Live rank's Window.
struct LiveRankLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveRankAttributes.self) { context in
            LiveRankActivityContent(state: context.state, selfLogin: context.attributes.selfLogin)
                .liveRankStale(context.isStale)
                // The Sample board's made-up people show initials, never a saved avatar.
                .environment(\.savedAvatars, context.attributes.savedAvatars)
                .widgetURL(context.state.boardURL)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveRankIslandLeading(state: state)
                        .liveRankStale(stale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveRankIslandTrailing(state: state)
                        .liveRankStale(stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveRankIslandBottom(state: state, selfLogin: context.attributes.selfLogin)
                        .environment(\.savedAvatars, context.attributes.savedAvatars)
                        .liveRankStale(stale)
                }
            } compactLeading: {
                LiveRankRankLabel(state: state, style: .compact)
                    .liveRankStale(stale)
            } compactTrailing: {
                LiveRankCountLabel(state: state, style: .compact)
                    .liveRankStale(stale)
            } minimal: {
                LiveRankRankLabel(state: state, style: .minimal)
                    .liveRankStale(stale)
            }
            // The default bottom margin left more room under the rows than between them; this
            // keeps the island inside its 160 pt cap with the rows' wider spacing.
            .contentMargins(.bottom, 12, for: .expanded)
            .widgetURL(state.boardURL)
            .keylineTint(.lime)
        }
        // The small family is what the CarPlay dashboard and Apple Watch's Smart Stack show.
        // Committed isn't a CarPlay app; supporting this family is all CarPlay needs.
        .supplementalActivityFamilies([.small])
    }
}

/// The Live Activity's non-island content, by family: the Lock Screen card, or the small layout
/// that CarPlay and Apple Watch show.
struct LiveRankActivityContent: View {
    let state: LiveRankState
    let selfLogin: String
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            LiveRankSmall(state: state)
        default:
            LiveRankLockScreen(state: state, selfLogin: selfLogin)
        }
    }
}

/// The expanded island's leading corner: the trophy and the Window. Inset from the region's edge:
/// flush, the island's corner curve clipped the trophy.
struct LiveRankIslandLeading: View {
    let state: LiveRankState

    var body: some View {
        LiveRankWindowLabel(state: state)
            .padding(.leading, 12)
    }
}

/// The expanded island's trailing corner: the age, or, with no rows to show, your count. The 10 pt
/// inset ends it where the rows' squares end.
struct LiveRankIslandTrailing: View {
    let state: LiveRankState

    var body: some View {
        Group {
            if state.hasLadder {
                UpdateAge(date: state.updatedDate)
            } else {
                LiveRankCountLabel(state: state, style: .expanded)
            }
        }
        .padding(.trailing, 10)
    }
}

/// The expanded island's bottom: the rows, or what Live rank is waiting for.
struct LiveRankIslandBottom: View {
    let state: LiveRankState
    let selfLogin: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.hasLadder {
                LiveRankRows(state: state, selfLogin: selfLogin)
            } else {
                if state.competitorCount <= 1, let line = state.emptyStateLine {
                    // Just you: your streak on this line, so the island keeps its height.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(line).font(.subheadline).foregroundStyle(Color.soft)
                        Spacer(minLength: 8)
                        LiveRankStreak(state: state, size: 15)
                    }
                }
                // The corners carry the Window and the count; the age goes here.
                LiveRankStatusLine(state: state)
            }
        }
        // A fixed-height presentation: three rows must not wrap off the bottom.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Lock Screen: the trophy and the Window with the age on the right, as the medium widget heads
/// itself, then the people above and below you in the board's rows. Without rows (no rivals, or no
/// count yet), your rank and count take their place, over the site's lit field,
/// which goes dark when the numbers are stale. The rows sit on plain ink: their squares glyph is a
/// mark that has to keep 3:1, and the field's lit squares would take that away.
struct LiveRankLockScreen: View {
    let state: LiveRankState
    let selfLogin: String
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LiveRankHeader(state: state)
            if state.hasLadder {
                LiveRankRows(state: state, selfLogin: selfLogin)
                    // Line the rows' content up with the header's.
                    .padding(.horizontal, -10)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    LiveRankRankLabel(state: state, style: .lockScreen)
                    Spacer(minLength: 8)
                    // Just you: your streak beside your count, on the same line (the card's
                    // height is capped).
                    LiveRankStreak(state: state, size: 17)
                    if state.contributions != nil || state.competitorCount <= 1 {
                        LiveRankCountLabel(state: state, style: .lockScreen)
                    }
                }
                if let line = LiveRankStatusLine.waiting(state) {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(isStale ? Color.warning : Color.soft)
                        .lineLimit(1)
                }
            }
        }
        // The card is a fixed height: past accessibility 1 the headline would clip, and the
        // rows would wrap long names off the bottom.
        .dynamicTypeSize(...(state.hasLadder ? DynamicTypeSize.xxLarge : .accessibility1))
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(alignment: .topTrailing) {
            if !isStale, !state.hasLadder {
                // The site's lit square field, still, behind the count. Text over it is white,
                // soft, or lime (`FieldTone.lockScreen`, checked in `ThemeTests`).
                SquareFieldCanvas(light: UnitPoint(x: 0.95, y: 0), reach: 0.5, cell: 12, gap: 3, tone: .lockScreen)
                    .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
            }
        }
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(.ink)
        .activitySystemActionForegroundColor(.lime)
    }
}

/// The small family: the CarPlay dashboard and Apple Watch's Smart Stack. It's read at a glance
/// from the driver's seat, so there are no rows. Your rank and count sit on one line, then the
/// Window and the age, or what Live rank is waiting for. Stale content steps its colors down.
/// CarPlay doesn't run buttons; a tap on iPhone opens the Board.
struct LiveRankSmall: View {
    let state: LiveRankState
    @Environment(\.liveRankIsStale) private var isStale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                LiveRankRankLabel(state: state, style: .small)
                Spacer(minLength: 8)
                if state.contributions != nil || state.competitorCount <= 1 {
                    LiveRankCountLabel(state: state, style: .small)
                }
            }
            if state.hasLadder {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let window = state.contributionWindow {
                        Text(window.shortTitle)
                            .font(.footnote)
                            .foregroundStyle(Color.soft)
                    }
                    Spacer(minLength: 4)
                    UpdateAge(date: state.updatedDate)
                }
            } else if let line = state.emptyStateLine {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(isStale ? Color.muted : Color.soft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        // A fixed, small surface: two lines must not wrap.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(.ink)
    }
}

private extension View {
    /// Stale numbers step down in color (see `LiveRankLiveActivity`), never in opacity, so they
    /// keep their contrast.
    func liveRankStale(_ isStale: Bool) -> some View {
        environment(\.liveRankIsStale, isStale)
    }
}

// MARK: - Previews

#if DEBUG
extension LiveRankState {
    static let previewMiddle = LiveRankState(
        window: "daily", rank: 3, competitorCount: 6, contributions: 7,
        above: .init(login: "odile-m", contributions: 9, movementToday: 0),
        below: .init(login: "ezra-q", contributions: 6, movementToday: -1),
        movementToday: 1, updatedAt: Int(Date().timeIntervalSince1970) - 240
    )
    static let previewNoRivals = LiveRankState(
        window: "weekly", rank: nil, competitorCount: 1, contributions: 38,
        above: nil, below: nil, movementToday: 0, updatedAt: Int(Date().timeIntervalSince1970) - 60
    )
    static let previewNoData = LiveRankState(
        window: "daily", rank: nil, competitorCount: 6, contributions: nil,
        above: nil, below: nil, movementToday: 0, updatedAt: Int(Date().timeIntervalSince1970)
    )
}

#Preview("Lock Screen", as: .content, using: LiveRankAttributes(selfLogin: "ari-linden")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
    LiveRankState.previewNoRivals
    LiveRankState.previewNoData
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: LiveRankAttributes(selfLogin: "ari-linden")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
}

#Preview("Compact", as: .dynamicIsland(.compact), using: LiveRankAttributes(selfLogin: "ari-linden")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
    LiveRankState.previewNoRivals
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: LiveRankAttributes(selfLogin: "ari-linden")) {
    LiveRankLiveActivity()
} contentStates: {
    LiveRankState.previewMiddle
}
#endif
