#!/usr/bin/env python3
"""Build an isolated fixture host for manual native userflow captures.

Uses current tracked SwiftUI views, in-memory standings, no Keychain, and no
Sparkle scheduling. The Captures menu chooses surfaces; sample counts are not
GitHub evidence. Never distribute this host as the product.
"""
import argparse
import pathlib
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--large-board", action="store_true", help="Seed 19 people to verify scrolling and lower-ranked rows")
parser.add_argument("--bundle-id", default="com.digg.committed.flowcapture", help="Use a separate app identity for concurrent previews")
args = parser.parse_args()
repo = pathlib.Path(__file__).resolve().parents[1]
destination = pathlib.Path(tempfile.mkdtemp(prefix="committed-capture-"))
files = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo).decode().split("\0")
for name in filter(None, files):
    source = repo / name
    if source.is_file():
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
app_file = destination / "CommitStandings/CommitStandingsApp.swift"
helpers = app_file.read_text().split("enum MenuPopoverLayout", 1)[1]
app_file.write_text(r'''import SwiftUI

@main struct FlowCaptureApp: App {
    @State private var surface = "Board"
    @State private var store: StandingsStore
    @State private var refresh: RefreshCoordinator
    @State private var roster: GitHubRoster
    @State private var auth = AuthModel(credentials: InMemoryGitHubCredentialStore(token: "fixture-only"), auth: GitHubAuth(clientID: "fixture", scope: ""))
    @State private var signedOut = AuthModel(credentials: InMemoryGitHubCredentialStore(), auth: GitHubAuth(clientID: "fixture", scope: ""))
    @State private var notifications = NotificationService()
    @State private var updater = AppUpdater(startingUpdater: false)

    init() {
        let s = StandingsStore(persistence: InMemoryCompetitorPersistence())
        try! s.addSelf(username: "octocat")
        for name in ["hubot", "monalisa", "defunkt", "mojombo"] { try! s.addRival(username: name) }
        if LARGE_BOARD {
            for number in 1...14 { try! s.addRival(username: "sample-rival-\(number)") }
        }
        for window in ContributionWindow.allCases {
            for (index, entry) in s.competitors.enumerated() {
                s.updateStanding(Standing(username: entry.username, contributions: (s.competitors.count-index)*8*window.dayCount,
                    window: window, lastUpdated: Date(), state: .loaded))
            }
        }
        let sources = GitHubRosterSnapshot(owner: "octocat", sources: [
            GitHubRosterSource(id: "org:github", title: "github", members: ["octocat", "hubot", "monalisa"]),
            GitHubRosterSource(id: "following", title: "People you follow", members: s.rivals.filter { $0.username != "monalisa" }.map(\.username))
        ], updatedAt: Date())
        let roster = GitHubRoster(store: s, credentials: InMemoryGitHubCredentialStore(token: "fixture-only"), fetch: { _ in
            GitHubRosterSnapshot(owner: sources.owner, sources: sources.sources, updatedAt: Date())
        })
        _roster = State(initialValue: roster)
        _store = State(initialValue: s)
        _refresh = State(initialValue: RefreshCoordinator(store: s, client: CaptureCounts(), beforeRefresh: { reason in
            await roster.refresh(force: reason == .manual)
        }))
    }

    var body: some Scene {
        WindowGroup("Committed · fixture capture") {
            Group {
                switch surface {
                case "Sign in": SignInView().environment(signedOut).padding(28).frame(width: 516, height: 476)
                case "People": FullRankingsView().frame(width: 420, height: 480)
                case "Help": ContributionsExplainerView()
                case "Signed-out popover": MenuContentView(updater: updater).environment(signedOut)
                default: MenuContentView(updater: updater)
                }
            }
            .environment(store).environment(refresh).environment(auth).environment(roster).environment(notifications)
            .preferredColorScheme(.light)
            .task { await roster.refresh() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Captures") {
                Button("Board") { surface = "Board" }.keyboardShortcut("1")
                Button("People") { surface = "People" }.keyboardShortcut("2")
                Button("Sign in") { surface = "Sign in" }.keyboardShortcut("3")
                Button("Help") { surface = "Help" }.keyboardShortcut("4")
                Button("Signed-out popover") { surface = "Signed-out popover" }.keyboardShortcut("5")
            }
        }
        Window("People", id: FullRankingsWindow.id) {
            FullRankingsView().environment(store).environment(refresh).environment(roster)
        }.defaultSize(width: 420, height: 480).windowResizability(.contentMinSize).windowToolbarStyle(.unifiedCompact)
        Window("How contributions are counted", id: ExplainerWindow.id) { ContributionsExplainerView() }
            .windowResizability(.contentSize)
    }
}

private struct CaptureCounts: ContributionsFetching {
    func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date) async -> Result<StandingCounts, ContributionsError> {
        .success(StandingCounts(contributions: (["octocat":40,"hubot":32,"monalisa":24,"defunkt":16,"mojombo":8][username] ?? 4) * window.dayCount))
    }
}

enum MenuPopoverLayout'''.replace('LARGE_BOARD', str(args.large_board).lower()) + helpers)
info = destination / "CommitStandings/Info.plist"
with info.open("rb") as stream:
    data = plistlib.load(stream)
data["LSUIElement"] = False
data["CFBundleDisplayName"] = "Committed"
with info.open("wb") as stream:
    plistlib.dump(data, stream)
print(f"Capture source: {destination}", flush=True)
subprocess.run(["xcodebuild", "-scheme", "CommitStandings", "-destination", "platform=macOS",
    "-derivedDataPath", str(destination / "build"), f"PRODUCT_BUNDLE_IDENTIFIER={args.bundle_id}",
    "SDK_STAT_CACHE_ENABLE=NO", "build"], cwd=destination, check=True)
print(f"Capture app: {destination}/build/Build/Products/Debug/CommitStandings.app")
