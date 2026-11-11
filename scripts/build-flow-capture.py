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
    // `-CaptureSurface Person` starts on that Captures entry (for `-CaptureSnapshot`).
    @State private var surface = UserDefaults.standard.string(forKey: "CaptureSurface") ?? "Board"
    @State private var store: StandingsStore
    @State private var refresh: RefreshCoordinator
    @State private var roster: GitHubRoster
    @State private var auth = AuthModel(credentials: InMemoryGitHubCredentialStore(token: "fixture-only"), auth: GitHubAuth(clientID: "fixture", scope: ""))
    @State private var signedOut = AuthModel(credentials: InMemoryGitHubCredentialStore(), auth: GitHubAuth(clientID: "fixture", scope: ""))
    @State private var notifications = NotificationService()
    @State private var updater = AppUpdater(startingUpdater: false)
    @State private var personWindow: PersonWindowModel

    init() {
        let s = StandingsStore(persistence: InMemoryCompetitorPersistence())
        try! s.addSelf(username: "octocat")
        for name in ["hubot", "monalisa", "defunkt", "mojombo"] { try! s.addRival(username: name) }
        if LARGE_BOARD {
            for number in 1...14 { try! s.addRival(username: "sample-rival-\(number)") }
        }
        let now = captureNow()
        // `-CaptureWaiting <login>` leaves that person's count unloaded: their row and person view wait.
        let waiting = UserDefaults.standard.string(forKey: "CaptureWaiting")
        let loaded = s.competitors.filter { $0.username != waiting }
        s.updateHistories(Dictionary(uniqueKeysWithValues: loaded.map { ($0.username, captureHistory($0.username, asOf: now)) }))
        for window in ContributionWindow.allCases {
            for entry in loaded {
                s.updateStanding(Standing(username: entry.username,
                    contributions: captureHistory(entry.username, asOf: now).total(for: window, asOf: now),
                    window: window, lastUpdated: now, state: .loaded))
            }
        }
        // `-CaptureWindow month` opens the board on that Window (a ContributionWindow raw value).
        if let window = UserDefaults.standard.string(forKey: "CaptureWindow").flatMap(ContributionWindow.init(rawValue:)) {
            s.selectedWindow = window
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
        // `-CapturePerson <login>` is who the person window shows (as if their row was clicked).
        let personWindow = PersonWindowModel(store: s, now: captureNow)
        personWindow.show(UserDefaults.standard.string(forKey: "CapturePerson") ?? "hubot")
        _personWindow = State(initialValue: personWindow)
        _refresh = State(initialValue: RefreshCoordinator(store: s, client: CaptureCounts(), now: captureNow, beforeRefresh: { reason in
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
                // `-CapturePersonDay 8` selects that day's bar instead of today's.
                case "Person": PersonWindowView(initialDay: UserDefaults.standard.object(forKey: "CapturePersonDay") as? Int)
                    .frame(width: PersonWindow.defaultWidth, height: 640)
                case "Signed-out popover": MenuContentView(updater: updater).environment(signedOut)
                default: MenuContentView(updater: updater)
                }
            }
            .environment(store).environment(refresh).environment(auth).environment(roster).environment(notifications)
            .environment(personWindow)
            // `-CaptureAppearance dark` captures in Dark Mode.
            .preferredColorScheme(UserDefaults.standard.string(forKey: "CaptureAppearance") == "dark" ? .dark : .light)
            .task { await roster.refresh() }
            .task { await snapshotIfRequested() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Captures") {
                Button("Board") { surface = "Board" }.keyboardShortcut("1")
                Button("People") { surface = "People" }.keyboardShortcut("2")
                Button("Sign in") { surface = "Sign in" }.keyboardShortcut("3")
                Button("Help") { surface = "Help" }.keyboardShortcut("4")
                Button("Signed-out popover") { surface = "Signed-out popover" }.keyboardShortcut("5")
                Button("Person") { surface = "Person" }.keyboardShortcut("6")
            }
        }
        Window("People", id: FullRankingsWindow.id) {
            FullRankingsView().environment(store).environment(refresh).environment(roster)
        }.defaultSize(width: 420, height: 480).windowResizability(.contentMinSize).windowToolbarStyle(.unifiedCompact)
        Window("How contributions are counted", id: ExplainerWindow.id) { ContributionsExplainerView() }
            .windowResizability(.contentSize)
        // Clicking a Board row opens the real person window, as in the app.
        Window("Person", id: PersonWindow.id) { PersonWindowView().environment(personWindow) }
            .defaultSize(width: PersonWindow.defaultWidth, height: 640).windowResizability(.contentMinSize)
            .windowToolbarStyle(.unifiedCompact)
    }
}

/// `-CaptureSnapshot <file.png>`: after the board settles, the host writes its own window's
/// contents to that PNG and quits, for captures where the shell can't record the screen.
@MainActor private func snapshotIfRequested() async {
    guard let path = UserDefaults.standard.string(forKey: "CaptureSnapshot") else { return }
    try? await Task.sleep(for: .seconds(4))
    guard let view = NSApp.windows.first(where: \.isVisible)?.contentView?.superview,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    NSApp.terminate(nil)
}

/// `-CaptureDate 2026-11-01T10:00:00Z` sets the host's clock, so the 1st's Final standings show.
private func captureNow() -> Date {
    UserDefaults.standard.string(forKey: "CaptureDate").flatMap { try? Date($0, strategy: .iso8601) } ?? Date()
}

private struct CaptureCounts: ContributionsFetching {
    func standingCounts(for username: String, window: ContributionWindow, asOf reference: Date) async -> Result<StandingCounts, ContributionsError> {
        let history = captureHistory(username, asOf: reference)
        return .success(StandingCounts(contributions: history.total(for: window, asOf: reference), history: history))
    }
}

/// A made-up year of days: a fixed count a day, a streak of the listed length (nothing the day
/// before it), then most days. monalisa's runs the whole calendar ("365+"); defunkt has none.
private func captureHistory(_ username: String, asOf reference: Date) -> ContributionHistory {
    let perDay = ["octocat": 5, "hubot": 4, "monalisa": 3, "defunkt": 2, "mojombo": 1][username] ?? 1
    let streak = ["octocat": 14, "hubot": 6, "monalisa": 371, "defunkt": 0, "mojombo": 2][username] ?? 1
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let today = calendar.startOfDay(for: reference)
    var days: [String: Int] = [:]
    for offset in 0..<371 {
        let day = calendar.date(byAdding: .day, value: -offset, to: today)!
        let active = offset < streak || (offset > max(streak, 1) && offset % 5 != 0)
        days[ContributionHistory.key(for: day, in: calendar)] = active ? perDay * (1 + offset % 3) : 0
    }
    return ContributionHistory(days: days, timeZone: .current)
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
