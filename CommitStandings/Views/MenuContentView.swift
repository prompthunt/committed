import SwiftUI

struct MenuContentView: View {
    @Environment(StandingsStore.self) private var store
    @Environment(RefreshCoordinator.self) private var refresh
    @Environment(AuthModel.self) private var auth
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var showOverflow = false
    @State private var contentHeight: CGFloat?
    // Persisted so dismissing a version stays dismissed across launches; an empty string
    // (the default) means nothing has been dismissed.
    @AppStorage("dismissedUpdateVersion") private var dismissedUpdateVersion: String = ""
    let updater: AppUpdater

    private var showUpdateBanner: Bool {
        UpdatePromptState.shouldShowBanner(
            updateAvailable: updater.updateAvailable,
            latestVersion: updater.latestVersion,
            dismissedVersion: dismissedUpdateVersion
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                HeaderBar(showOverflow: $showOverflow)
                    .padding(.bottom, 8)
                // Full-bleed hairline under the title bar (Port-Menu style); negative inset cancels
                // the outer 12pt padding so it spans edge to edge.
                Divider()
                    .padding(.horizontal, -12)
                    .padding(.bottom, 10)
                ScrollView {
                    VStack(spacing: 0) {
                        if showUpdateBanner, let version = updater.latestVersion {
                            UpdateBanner(
                                version: version,
                                onUpdate: { updater.installUpdate() },
                                onDismiss: { dismissedUpdateVersion = version }
                            )
                            .padding(.bottom, 10)
                        }
                        content
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        min(geometry.size.height.rounded(.up), MenuPopoverLayout.maxHeight)
                    } action: { height in
                        contentHeight = height
                    }
                }
                // ScrollView otherwise accepts all proposed space, even for a short board.
                // Its ideal height comes from the content; the outer cap limits the viewport.
                .frame(minHeight: 0, idealHeight: contentHeight, maxHeight: contentHeight)
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.never)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .top)
            .accessibilityHidden(showOverflow)
            .overlay {
                if showOverflow {
                    Button { showOverflow = false } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss settings")
                    .keyboardShortcut(.cancelAction)
                }
            }

            // ⋯ overflow renders inline (an overlay, not a nested popover) so it opens instantly
            // with no focus fight. A transparent backdrop catches outside taps to dismiss.
            if showOverflow {
                OverflowMenu(updater: updater) { showOverflow = false }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 34)
                    .padding(.trailing, 10)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: MenuPopoverLayout.width)
        .frame(maxHeight: MenuPopoverLayout.maxHeight, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .containerBackground(
            reduceTransparency || contrast == .increased
                ? AnyShapeStyle(.background) : AnyShapeStyle(.regularMaterial),
            for: .window
        )
        .onExitCommand { showOverflow = false }
        .onChange(of: store.selectedWindow) {
            // Only refresh when the new window's data is actually stale/missing — otherwise
            // toggling between Today/7/30 days flashed "updating…" on every switch. Cached
            // windows show instantly. `.windowChanged` doesn't force a LOC re-sync.
            if auth.isSignedIn, refresh.needsRefresh(for: store.selectedWindow) {
                Task { await refresh.refreshAll(reason: .windowChanged) }
            }
        }
    }

    @ViewBuilder private var content: some View {
        // Sign-in lives in a standalone window that survives the browser hand-off.
        if OnboardingFlow.step(isSignedIn: auth.isSignedIn) != .complete {
            OnboardingPrompt()
        } else {
            VStack(spacing: 0) {
                RosterStatusView().frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                if store.hasSelf {
                    ContributionWindowPicker()
                        // Equal, roomier breathing room above and below the hero so it doesn't
                        // hug the segmented tabs.
                        .padding(.bottom, 14)
                    // "You" card up top: your first name, handle, and contributions for the
                    // window. Sits above the list in both states.
                    HeroCard()
                        .padding(.bottom, 14)
                }
                if !store.hasSelf {
                    EmptyStateView()
                } else if store.rivals.isEmpty {
                    SoloView()
                } else {
                    LeaderboardView()
                }
                if store.hasSelf {
                    PrivateContributionsTip()
                        .padding(.top, 12)
                }
            }
        }
    }
}

/// Compact signed-out state shown in the popover: a launcher that opens the full onboarding
/// window (and brings the app forward) rather than running the cramped device-flow inline.
private struct OnboardingPrompt: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            Image("github-mark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundStyle(.primary)
            Text("Finish setting up to see your standings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Set up Committed") {
                OnboardingWindow.open(openWindow)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

/// Title bar: product name on the left, the `⋯` overflow toggle on the right. The overflow
/// content renders inline (see `OverflowMenu`, an overlay in `MenuContentView`) rather than as a
/// nested popover — so it opens instantly and keeps native toggles and buttons in the same panel.
struct HeaderBar: View {
    @Binding var showOverflow: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.appName)
                .font(.headline)
            Spacer()
            // Ghost button: transparent at rest, a subtle rounded fill on hover (and while the
            // menu is open).
            Button { showOverflow.toggle() } label: {
                Image(systemName: "ellipsis")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.primary.opacity(hovering || showOverflow ? 0.12 : 0))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("More")
            .accessibilityLabel("More settings and actions")
            .accessibilityValue(showOverflow ? "Expanded" : "Collapsed")
        }
    }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Committed"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

#Preview("Username entry") {
    let store = StandingsStore(persistence: InMemoryCompetitorPersistence())
    let refresh = RefreshCoordinator(store: store, client: StubClient())
    return EmptyStateView()
        .environment(store)
        .environment(refresh)
        .frame(width: 320)
}

private struct StubClient: ContributionsFetching {
    func standingCounts(
        for username: String,
        window: ContributionWindow,
        asOf reference: Date
    ) async -> Result<StandingCounts, ContributionsError> {
        .success(StandingCounts(contributions: 42))
    }
}
