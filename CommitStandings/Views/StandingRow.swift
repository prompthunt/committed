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

    var body: some View {
        HStack(spacing: 10) {
            Text("#\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            AvatarView(username: competitor.username, size: 26)
            HStack(spacing: 4) {
                Text(competitor.username)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fontWeight(competitor.isSelf ? .semibold : .regular)
                if competitor.isSelf {
                    Text("you")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.18), in: .capsule)
                        .foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                rankDeltaIndicator
                contributionsLabel
                    .frame(minWidth: 40, alignment: .trailing)
            }
            contributionSquare
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(selfHighlight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Your own row gets the same treatment as the hero card: a soft tint fill with a thin tint
    /// hairline border, so "you" reads consistently in the card and the list.
    @ViewBuilder
    private var selfHighlight: some View {
        if competitor.isSelf {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.tint.opacity(0.30), lineWidth: 1)
                )
        }
    }

    /// A small, quiet chevron showing how this row moved since the start of the day: a single
    /// chevron for a one-spot move, a double chevron for two or more. Up is green, down is muted so
    /// it never feels like a scolding. Nothing renders when the position held.
    @ViewBuilder
    private var rankDeltaIndicator: some View {
        if let delta = rankDelta, delta != 0 {
            Image(systemName: deltaSymbol(delta))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(delta > 0 ? Color.green : Color.secondary)
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
        if hasData, let standing {
            Image(systemName: "square.grid.2x2.fill")
                .imageScale(.small)
                .foregroundStyle(ContributionShade.color(value: standing.contributions, max: maxContributions))
                .frame(width: 16)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: 16)
        }
    }

    var accessibilityDescription: String {
        let movement = rankDelta.map { delta in
            delta == 0 ? "" : ", \(delta > 0 ? "up" : "down") \(delta.magnitude) \(delta.magnitude == 1 ? "place" : "places") today"
        } ?? ""
        return standingDescription + movement
    }

    private var standingDescription: String {
        let who = competitor.isSelf ? "you" : competitor.username
        switch standing?.state {
        case .failed(let message) where !hasData:
            return "rank \(rank), \(who), no data: \(message)"
        case .failed(let message):
            return "rank \(rank), \(who), stale, \(contributionsText) contributions for \(window.accessibilityDescription). Refresh failed: \(message)"
        case .loading where !hasData:
            return "rank \(rank), \(who), loading"
        default:
            return "rank \(rank), \(who), \(contributionsText) contributions for \(window.accessibilityDescription)"
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
                .font(.callout.monospacedDigit())
                .foregroundStyle(.orange)
        default:
            Text(contributionsText)
                .font(.callout.monospacedDigit())
                .fontWeight(competitor.isSelf ? .semibold : .regular)
                .pulsing(isRefreshing)
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
