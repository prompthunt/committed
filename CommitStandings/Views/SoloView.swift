import SwiftUI

/// The "you" card pinned to the top of the board (below the tabs): your avatar, your first name
/// over your @handle, and the selected window's contribution count as a big condensed number with
/// a small uppercase "CONTRIBUTIONS" caption. Shown in both the solo and the populated board so
/// there's always a sense of where you stand. (Your rank is visible in the list below; the
/// explainer stays reachable from the ⋯ "About Committed" menu.)
struct HeroCard: View {
    @Environment(StandingsStore.self) private var store
    @Environment(AuthModel.self) private var auth
    @Environment(RefreshCoordinator.self) private var refresh

    /// Last month's Final standings while the board shows them: the card shows your total for it.
    private var finals: FinalStandings? {
        refresh.showsFinalStandings && !store.rivals.isEmpty ? refresh.offeredFinalStandings : nil
    }

    var body: some View {
        if let me = store.selfCompetitor {
            let standing = store.standing(for: me.username, window: store.selectedWindow)
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
                    if let finals {
                        Text("in \(finals.month.name)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .tracking(8 * 0.14)
                            .textCase(.uppercase)
                            .foregroundStyle(.tint)
                            .padding(.top, 2)
                    } else if let day = store.selectedWindow.dayOfMonth(asOf: Date()) {
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
            .accessibilityLabel(accessibilityLabel(for: standing))
        }
    }

    /// The contribution count once it has actually loaded (nil while first loading / on failure).
    private func value(for standing: Standing?) -> Int? {
        if let finals { return finals.you?.contributions }
        guard let standing, standing.lastUpdated != .distantPast else { return nil }
        return standing.contributions
    }

    private func headline(for standing: Standing?) -> String {
        value(for: standing).map { $0.formatted() } ?? "—"
    }

    private func accessibilityLabel(for standing: Standing?) -> String {
        let who = store.selfCompetitor.map { "@\($0.username)" } ?? "you"
        guard let value = value(for: standing) else {
            return "\(who), no contributions data yet"
        }
        if let finals {
            return "\(who), \(value) contributions in \(finals.month.name)"
        }
        let day = store.selectedWindow.dayOfMonth(asOf: Date()).map { ", \($0.lowercased())" } ?? ""
        return "\(who), \(value) contributions for \(store.selectedWindow.accessibilityDescription)\(day)"
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
