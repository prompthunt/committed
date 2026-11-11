import SwiftUI

/// How the private-contributions tip is drawn. The Mac uses `.standard` (system colors, a tinted
/// outlined card and a small bordered link); the iPhone sets `\.privateContributionsTipStyle` to
/// its own materials and gives the link its button style from outside, the way it restyles
/// `StandingRow` and the person view. A nil color means the system's (`.tint` for the icon,
/// `.secondary` for text).
struct PrivateContributionsTipStyle {
    var iconColor: Color? = nil
    var textFont: Font = .caption
    /// The instructions' color.
    var instructionColor: Color? = nil
    /// The privacy note's and the dismiss button's color.
    var noteColor: Color? = nil
    var spacing: CGFloat = 8
    var padding: CGFloat = 11
    /// The dismiss button's minimum tap target; its header then tucks up by `headerInset`.
    var dismissTarget: CGFloat = 0
    var headerInset: CGFloat = 0
    /// The card's fill and outline. nil = the Mac's tinted fill with a tinted outline.
    var cardColor: Color? = nil
    var cardStroke: Color = .clear
    var cornerRadius: CGFloat = 10
    /// The Mac's small bordered link. Off, the link shows an arrow and takes the surrounding
    /// button style.
    var systemLink = true

    static let standard = PrivateContributionsTipStyle()
}

extension EnvironmentValues {
    @Entry var privateContributionsTipStyle = PrivateContributionsTipStyle.standard
}

/// Shared setup reminder for onboarding, the board and your own person view, on the Mac and the
/// iPhone (one copy, one dismissal). The explainer keeps it available after dismissal. We read
/// the public graph and cannot detect this setting per user.
struct PrivateContributionsTip: View {
    @AppStorage("dismissedPrivateContribTip") private var dismissed = false
    @Environment(\.privateContributionsTipStyle) private var style
    var dismissible = true

    private static let helpURL = URL(string: "https://docs.github.com/en/account-and-profile/how-tos/contribution-settings/manage-visibility-settings-for-private-contributions-and-achievements")!

    var body: some View {
        if !dismissible || !dismissed {
            VStack(alignment: .leading, spacing: style.spacing) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open")
                        .foregroundStyle(color(style.iconColor, or: .tint))
                    Text("Want your private work to count?")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    if dismissible {
                        Button {
                            dismissed = true
                        } label: {
                            Image(systemName: "xmark").imageScale(.small)
                                .foregroundStyle(color(style.noteColor, or: .secondary))
                                .frame(minWidth: style.dismissTarget, minHeight: style.dismissTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss tip")
                    }
                }
                .padding(.bottom, dismissible ? style.headerInset : 0)
                Text("Include private repo and org activity: on your GitHub profile, above the green squares, choose **Contribution settings → Private contributions**.")
                    .font(style.textFont)
                    .foregroundStyle(color(style.instructionColor, or: .secondary))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Only daily counts are shared. Your code and repo details stay private.")
                    .font(style.textFont)
                    .foregroundStyle(color(style.noteColor, or: .secondary))
                    .fixedSize(horizontal: false, vertical: true)
                link
            }
            .padding(style.padding)
            .background(card)
            .overlay(outline)
        }
    }

    @ViewBuilder
    private var link: some View {
        if style.systemLink {
            Link("How to enable on GitHub", destination: Self.helpURL)
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else {
            Link(destination: Self.helpURL) {
                Label("How to enable on GitHub", systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
            .padding(.top, 4)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var card: some View {
        if let fill = style.cardColor {
            shape.fill(fill)
        } else {
            shape.fill(.tint.opacity(0.12))
        }
    }

    @ViewBuilder
    private var outline: some View {
        if style.cardColor == nil {
            shape.stroke(.tint.opacity(0.35), lineWidth: 1)
        } else {
            shape.strokeBorder(style.cardStroke, lineWidth: 1)
        }
    }

    private func color(_ color: Color?, or fallback: some ShapeStyle) -> AnyShapeStyle {
        color.map(AnyShapeStyle.init) ?? AnyShapeStyle(fallback)
    }
}
