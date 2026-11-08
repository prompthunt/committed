import SwiftUI

/// The slim reminder at the top of the Board and People while the Sample board is showing:
/// "Sample board · Connect GitHub". Tapping it starts Connect GitHub, which replaces the Sample
/// board with your real one.
struct SampleBoardBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Task { await model.connectGitHub() }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.lime)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text("Sample board \(Text("·").foregroundStyle(Color.muted)) \(Text("Connect GitHub").foregroundStyle(Color.lime))")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .imageScale(.small)
                    .foregroundStyle(Color.lime)
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color.raised, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.lime.opacity(0.28), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sample board. Connect GitHub")
        .accessibilityHint("Replaces the sample board with your real one.")
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

extension View {
    /// Pins `SampleBoardBanner` above the content while the Sample board is showing.
    func sampleBoardBanner() -> some View {
        modifier(SampleBoardBannerInset())
    }
}

private struct SampleBoardBannerInset: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if model.mode == .sampleBoard {
                SampleBoardBanner()
                    .readableContentWidth()
            }
        }
    }
}
