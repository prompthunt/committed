import SwiftUI

/// The "you" card pinned to the top of the board (below the tabs): your avatar, your first name
/// over your @handle, and the selected window's contribution count as a big condensed number with
/// a small uppercase "CONTRIBUTIONS" caption, with your streak ("🔥 12") under your handle once
/// your count has loaded. Shown in both the solo and the populated board so there's always a sense
/// of where you stand. (Your rank is visible in the list below; the explainer stays reachable from
/// the ⋯ "About Committed" menu.)
struct HeroCard: View {
    @Environment(StandingsStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @Environment(RefreshCoordinator.self) private var refresh

    var body: some View {
        if let me = store.selfCompetitor {
            let standing = store.standing(for: me.username, window: store.selectedWindow)
            let streak = value(for: standing) == nil ? nil : refresh.streak(for: me.username)
            HStack(spacing: 14) {
                AvatarView(username: me.username, size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    if let firstName = DisplayName.firstName(from: auth.displayName) {
                        Text(firstName)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("@\(me.username)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        // No display name yet (or none set) — show just the handle, never a
                        // fake-capitalized username.
                        Text("@\(me.username)")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let streakText = StreakLabel.text(streak) {
                        Text(streakText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .center, spacing: 1) {
                    Text(headline(for: standing))
                        .font(.system(size: 38, weight: .semibold).width(.condensed))
                        .tracking(38 * -0.03)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("contributions")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(8 * 0.14)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    // This month: "Day 10 of 30", so you know how much race is left.
                    if let day = store.selectedWindow.dayOfMonth(asOf: Date()) {
                        Text(day)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .tracking(8 * 0.14)
                            .textCase(.uppercase)
                            .foregroundStyle(.tint)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.tint.opacity(0.30), lineWidth: 1)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(
                username: me.username, contributions: value(for: standing),
                window: store.selectedWindow, dayOfMonth: store.selectedWindow.dayOfMonth(asOf: Date()),
                streak: streak))
        }
    }

    /// The contribution count once it has actually loaded (nil while first loading / on failure).
    private func value(for standing: Standing?) -> Int? {
        guard let standing, standing.lastUpdated != .distantPast else { return nil }
        return standing.contributions
    }

    private func headline(for standing: Standing?) -> String {
        value(for: standing).map { $0.formatted() } ?? "—"
    }

    /// One sentence for the card. The streak is read only beside a loaded count.
    static func accessibilityLabel(username: String, contributions: Int?, window: ContributionWindow,
                                   dayOfMonth: String? = nil, streak: Int?) -> String {
        guard let contributions else {
            return "@\(username), no contributions data yet"
        }
        let streak = StreakLabel.spoken(streak).map { ", " + $0 } ?? ""
        let day = dayOfMonth.map { ", \($0.lowercased())" } ?? ""
        return "@\(username), \(contributions) contributions for \(window.accessibilityDescription)\(day)\(streak)"
    }
}

/// GitHub is the source of truth even when your circle is empty.
struct SoloView: View {
    @Environment(StandingsStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 8) {
            Text(store.competitors.count > 1 ? "Your circle is hidden" : "Your circle starts here").font(.callout.weight(.semibold))
            Text(store.competitors.count > 1
                 ? "Show people again in People whenever you like."
                 : "Follow people on GitHub or join an organization to see them on your board automatically.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("People…") { FullRankingsWindow.open(openWindow) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}
