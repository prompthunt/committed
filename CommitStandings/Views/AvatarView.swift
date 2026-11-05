import SwiftUI

/// Avatar showing the user's real GitHub avatar (`github.com/{username}.png`),
/// falling back to a colored initials circle while loading or on failure.
struct AvatarView: View {
    let username: String
    var size: CGFloat = 32
    @Environment(\.loadsGitHubAvatars) private var loadsGitHubAvatars

    private var avatarURL: URL? {
        URL(string: "https://github.com/\(username).png?size=\(Int(size * 2))")
    }

    var body: some View {
        AsyncImage(url: loadsGitHubAvatars ? avatarURL : nil) { phase in
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
    /// The iPhone's quieter fallback; nil on the Mac (a colored circle).
    @Environment(\.avatarFallbackStyle) private var fallbackStyle

    var body: some View {
        if let fallbackStyle {
            Circle()
                .fill(fallbackStyle.fill)
                .overlay { Circle().strokeBorder(fallbackStyle.stroke, lineWidth: 1) }
                .overlay(
                    Text(AvatarColor.letterInitials(for: username))
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(fallbackStyle.text)
                )
        } else {
            coloredCircle
        }
    }

    private var coloredCircle: some View {
        Circle()
            .fill(AvatarColor.color(for: username).gradient)
            .overlay(
                Text(AvatarColor.initials(for: username))
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

/// A fallback avatar drawn as a quiet tile instead of a colored circle, with letters-only
/// initials. The iPhone sets it; the Mac leaves it nil.
struct AvatarFallbackStyle {
    var fill: Color
    var stroke: Color
    var text: Color
}

extension EnvironmentValues {
    @Entry var avatarFallbackStyle: AvatarFallbackStyle? = nil
    /// Off for sample and screenshot data, so a made-up username never shows a real account's
    /// avatar; rows show colored initials instead.
    @Entry var loadsGitHubAvatars = true
}
