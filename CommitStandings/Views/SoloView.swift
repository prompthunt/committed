import SwiftUI

/// The "you" card pinned to the top of the board (below the tabs): your avatar, your first name
/// over your @handle, and the selected window's contribution count as a big condensed number with
/// a small uppercase "CONTRIBUTIONS" caption. Shown in both the solo and the populated board so
/// there's always a sense of where you stand. (Your rank is visible in the list below; the
/// explainer stays reachable from the ⋯ "About Committed" menu.)
struct HeroCard: View {
    @Environment(StandingsStore.self) private var store
    @Environment(AuthModel.self) private var auth

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
        return "\(who), \(value) contributions for \(store.selectedWindow.accessibilityDescription)"
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

/// Avatar showing the user's real GitHub avatar (`github.com/{username}.png`),
/// falling back to a colored initials circle while loading or on failure.
struct AvatarView: View {
    let username: String
    var size: CGFloat = 32

    private var avatarURL: URL? {
        URL(string: "https://github.com/\(username).png?size=\(Int(size * 2))")
    }

    var body: some View {
        AsyncImage(url: avatarURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                InitialsCircle(username: username, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// The colored-initials placeholder/fallback used when a GitHub avatar is loading
/// or unavailable.
struct InitialsCircle: View {
    let username: String
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(AvatarColor.color(for: username).gradient)
            .overlay(
                Text(AvatarColor.initials(for: username))
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}
