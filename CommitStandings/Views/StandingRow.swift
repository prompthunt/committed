import SwiftUI

struct StandingRow: View {
    let rank: Int
    let competitor: Competitor
    let standing: Standing?
    let window: ContributionWindow
    /// The largest contribution count among the rows being shown, so the green square can be
    /// shaded relative to the leader (GitHub-style). 0 ⇒ no shading reference yet.
    var maxContributions: Int = 0
    /// Change in this row's placement since the start of the day (+ up, − down). nil/0 ⇒ no marker.
    var rankDelta: Int? = nil
    /// A finished month's medal, shown before the name (Final standings only).
    var medal: Medal? = nil
    /// What the count covers when it isn't `window` ("October" on Final standings), for VoiceOver.
    var period: String? = nil
    /// Grows with Dynamic Type on iPhone so "#12" never truncates; stays 24pt on the Mac.
    @ScaledMetric(relativeTo: .caption) private var rankWidth: CGFloat = 24
    /// iPhone at accessibility text sizes wraps long usernames instead of truncating them.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The Mac's look by default; the iPhone sets its own (see `StandingRowStyle`).
    @Environment(\.standingRowStyle) private var style

    var body: some View {
        HStack(spacing: style.spacing) {
            Text("#\(rank)")
                .font(style.rankFont)
                .foregroundStyle(style.rankColor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .frame(width: rankWidth * style.rankWidthScale, alignment: .trailing)
            AvatarView(username: competitor.username, size: style.avatarSize)
            HStack(spacing: 4) {
                if let medal {
                    Text(medal.emoji)
                        .font(style.nameFont)
                        .accessibilityHidden(true)
                }
                Text(competitor.username)
                    .font(competitor.isSelf ? style.selfNameFont : style.nameFont)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .truncationMode(.middle)
                if competitor.isSelf, style.showsSelfBadge {
                    Text("you")
                        .font(style.badgeFont)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(accent.opacity(style.badgeFillOpacity), in: .capsule)
                        .foregroundStyle(style.badgeForeground.map(AnyShapeStyle.init) ?? accent)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                rankDeltaIndicator
                contributionsLabel
                    .fixedSize(horizontal: style.keepsCountWhole, vertical: false)
                    .frame(minWidth: style.countMinWidth, alignment: .trailing)
            }
            contributionSquare
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(selfHighlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Your own row gets the same treatment as the hero card: a soft tint fill with a thin tint
    /// hairline border, so "you" reads consistently in the card and the list.
    @ViewBuilder
    private var selfHighlight: some View {
        if competitor.isSelf {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(accent.opacity(style.selfFillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .stroke(accent.opacity(style.selfStrokeOpacity), lineWidth: 1)
                )
        }
    }

    /// The badge and highlight color: the style's accent, or the tint (the Mac).
    private var accent: AnyShapeStyle {
        style.accent.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint)
    }

    /// A small, quiet chevron showing how this row moved since the start of the day: a single
    /// chevron for a one-spot move, a double chevron for two or more. Up is green, down is muted so
    /// it never feels like a scolding. Nothing renders when the position held.
    @ViewBuilder
    private var rankDeltaIndicator: some View {
        if let delta = rankDelta, delta != 0 {
            Image(systemName: deltaSymbol(delta))
                .font(style.movementFont)
                .foregroundStyle(delta > 0 ? style.movementUpColor : (style.movementDownColor ?? Color.secondary))
                .accessibilityLabel(delta > 0 ? "up \(delta)" : "down \(-delta)")
        }
    }

    private func deltaSymbol(_ delta: Int) -> String {
        switch delta {
        case 2...: return "chevron.up.2"
        case 1: return "chevron.up"
        case -1: return "chevron.down"
        default: return "chevron.down.2"
        }
    }

    /// A small green square (à la the GitHub contribution graph) right of the number — lighter for
    /// low counts, richer/darker green for high. Hidden when there's no data yet.
    @ViewBuilder
    private var contributionSquare: some View {
        switch style.squares {
        case .symbol:
            if hasData, let standing {
                Image(systemName: "square.grid.2x2.fill")
                    .imageScale(.small)
                    .foregroundStyle(ContributionShade.color(value: standing.contributions, max: maxContributions))
                    .frame(width: 16)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 16)
            }
        case .shadedSymbol(let colors):
            // The same glyph, shaded by quartile of the leader's count.
            if hasData, let standing, !colors.isEmpty {
                let level = min(SquareRamp.level(value: standing.contributions, max: maxContributions), colors.count - 1)
                Image(systemName: "square.grid.2x2.fill")
                    .imageScale(.small)
                    .foregroundStyle(colors[level])
                    .frame(width: 16)
                    .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 16)
            }
        case .hidden:
            EmptyView()
        }
    }

    var accessibilityDescription: String {
        let movement = rankDelta.map { delta in
            delta == 0 ? "" : ", \(delta > 0 ? "up" : "down") \(delta.magnitude) \(delta.magnitude == 1 ? "place" : "places") today"
        } ?? ""
        return standingDescription + movement + (medal.map { ", \($0) medal" } ?? "")
    }

    /// "for today", or "in October" on Final standings.
    private var periodDescription: String {
        period.map { "in \($0)" } ?? "for \(window.accessibilityDescription)"
    }

    private var standingDescription: String {
        let who = competitor.isSelf ? "you" : competitor.username
        switch standing?.state {
        case .failed(let message) where !hasData:
            return "rank \(rank), \(who), no data: \(message)"
        case .failed(let message):
            return "rank \(rank), \(who), stale, \(contributionsText) contributions \(periodDescription). Refresh failed: \(message)"
        case .loading where !hasData:
            return "rank \(rank), \(who), loading"
        default:
            return "rank \(rank), \(who), \(contributionsText) contributions \(periodDescription)"
        }
    }

    private var hasData: Bool {
        guard let standing else { return false }
        return standing.lastUpdated != .distantPast
    }

    /// A row with cached numbers that's fetching fresh ones: keep the value visible and
    /// pulse it, rather than swapping in a spinner.
    private var isRefreshing: Bool {
        standing?.state == .loading && hasData
    }

    private var contributionsText: String {
        guard let standing, hasData else { return "—" }
        return standing.contributions.formatted()
    }

    @ViewBuilder
    private var contributionsLabel: some View {
        switch standing?.state {
        case .loading where !hasData:
            SkeletonCell()
        case .failed where !hasData:
            Text("—")
                .font(style.countFont)
                .foregroundStyle(.orange)
        default:
            if competitor.isSelf, let color = style.selfCountColor {
                Text(contributionsText)
                    .font(style.selfCountFont)
                    .foregroundStyle(color)
                    .pulsing(isRefreshing)
            } else {
                Text(contributionsText)
                    .font(competitor.isSelf ? style.selfCountFont : style.countFont)
                    .pulsing(isRefreshing)
            }
        }
    }
}

/// Maps a contribution count to a green shade relative to the leader — light mint for low,
/// richer/darker green for high — staying visible on the dark background. Mirrors the feel of
/// the GitHub contribution-graph scale.
enum ContributionShade {
    static func color(value: Int, max: Int) -> Color {
        let fraction = max > 0 ? min(1.0, Double(value) / Double(max)) : 0
        // Light mint (#9be9a8) → vivid green (#2ea043). Higher = darker/richer, still legible dark.
        let lo = (r: 0.61, g: 0.91, b: 0.66)
        let hi = (r: 0.18, g: 0.63, b: 0.26)
        return Color(
            red: lo.r + (hi.r - lo.r) * fraction,
            green: lo.g + (hi.g - lo.g) * fraction,
            blue: lo.b + (hi.b - lo.b) * fraction
        )
    }
}

/// A placeholder bar shown in the contributions cell during the first-ever load, in place
/// of a spinner. Pulses on its own so a board full of them breathes in unison.
struct SkeletonCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.quaternary)
            .frame(width: 30, height: 9)
            .pulsing(true)
    }
}

/// Gently animates opacity while `active`, signalling "this value is refreshing"
/// without a layout-shifting spinner. Settles back to fully opaque when inactive.
private struct PulseModifier: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    private var shouldPulse: Bool { active && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(shouldPulse && dimmed ? 0.4 : 1.0)
            .onChange(of: shouldPulse, initial: true) { _, isActive in
                if isActive {
                    withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                        dimmed = true
                    }
                } else {
                    withAnimation(nil) {
                        dimmed = false
                    }
                }
            }
    }
}

extension View {
    /// Pulse this view's opacity while `active` (e.g. a stale value being refreshed).
    func pulsing(_ active: Bool) -> some View {
        modifier(PulseModifier(active: active))
    }
}
