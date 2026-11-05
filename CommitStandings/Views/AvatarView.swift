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

extension EnvironmentValues {
    /// Off for sample and screenshot data, so a made-up username never shows a real account's
    /// avatar; rows show colored initials instead.
    @Entry var loadsGitHubAvatars = true
}
