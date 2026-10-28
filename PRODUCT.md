# Committed

Committed puts a friendly GitHub leaderboard in your Mac’s menu bar or Windows tray.

For contributors, designers, and agents. Last reviewed: 2026-10-23. Positioning and voice guidance live in [Product Marketing Context](.agents/product-marketing.md).

## What it is

Committed is a Mac **menu-bar app** and Windows **tray app** for comparing GitHub contributions with friends. Connect GitHub to load the people you follow and members of your GitHub organizations, then hide anyone you don't want on your board.

Open the menu bar to see where you stand today or over the last 7 or 30 days. Your rank follows the contribution count on your GitHub profile.

## Who it's for

- **Primarily:** developers on Macs or Windows PCs who enjoy friendly competition and want to see how their GitHub contributions compare with friends and people they follow.
- **Also:** teammates who want that same friendly competition with people in their GitHub organizations.

Each user gets a personal board based on their GitHub connections. Friends do not need to install Committed to appear on it; their counts come from their public GitHub contribution graphs.

The leaderboard compares activity counts. It does not assess code quality or work performance.

## Core loop

1. Connect GitHub and let your people load automatically.
2. Open the menu bar to compare contributions for Today, 7 days, or 30 days.
3. Check back as the board refreshes, or turn on notifications to hear when you pass someone or they pass you.

## What it does

Clicking the menu-bar icon opens a popover with your contribution summary and a ranked leaderboard. Each row is a person you've kept visible on your board:

- **Rank + avatar + username** — pulled from real GitHub avatars; your own row is marked with a **"you"** badge.
- **Contributions** — the single ranking metric: the GitHub contribution-graph "green squares" count for the selected window. Rows are sorted by contributions, highest first.
- **Your summary** — your avatar, name or handle, and contribution count appear above the list. Your rank also appears in the menu bar when you have visible rivals.
- **Today's movement** — small chevrons show rank changes since the first refresh of the day. Hiding or showing people starts a new movement baseline.
- **Leaderboard Notifications** — opt in through `⋯` to receive a notification when someone passes you or you pass them.

### Time windows

A segmented control at the top switches the window; the contribution count recomputes for it:

- **Today** — the current day.
- **7 days** — the trailing 7 days.
- **30 days** — the trailing 30 days.

All three windows are available once the contribution data loads; there is no history-building or backfill period. The app sums the daily counts for the selected range.

### Refresh behavior the user notices

- The board **refreshes itself** in the background about every 5 minutes.
- Opening the menu refreshes only if the data is stale (older than ~2 minutes), so re-opening doesn't constantly flash "updating".
- Switching windows shows cached numbers instantly and only fetches when that window's data is stale or missing.
- **Refresh** in the `⋯` menu reloads both the GitHub people list and contribution counts.
- During a refresh, cached values remain visible and **pulse** gently. The first load uses placeholders and a "Fetching the first set of standings" message.
- People-sync status appears on the board and in **People…**. The contribution refresh age appears beside **Refresh** in the `⋯` menu.

### Connecting GitHub and managing people

- **Connect GitHub** runs in a standalone setup window that stays open during the browser hand-off. The app shows a code, you approve it on GitHub, and the token is stored in the macOS Keychain. There is no Committed account: connecting authorizes the app's read-only GitHub access on that Mac, and **Disconnect GitHub** deletes the token.
- After approval, you go directly to the board while your people load. It includes you, accessible members of your GitHub organizations, and people **you** follow. It does not crawl teammates’ following lists.
- Each username appears once on the board, even when you share multiple connections. The people list syncs when you connect or first open the board, then about every 15 minutes during background refreshes. Manual **Refresh** forces a sync.
- **People…** opens a native alphabetical list with search and **All / Following / Organizations** filters. Click the eye to hide someone or the eye-slash to show them again. Hidden people stay in the list so you can restore them. You cannot hide yourself; there is no manual add or remove flow.
- The app loads every page of organizations, members, and follows. Only a complete successful fetch replaces the saved people list. Failed requests preserve that list and show a retry message. Organizations that GitHub does not expose to the app cannot appear.
- Visibility choices are saved **locally on each Mac, per GitHub account**. They survive relaunch, disconnecting and reconnecting, refreshes, and someone leaving and rejoining a source. Hiding someone does not change your GitHub follows or membership. Hidden people are excluded from rankings, contribution refreshes, and crossing notifications.
- When upgrading from the old manual list, the first successful sync saves a local backup (`competitors.manual-backup.v1`). People you still follow or share an organization with retain their cached counts and row identities. People outside those sources leave the active board. Disconnecting clears the active account cache but keeps its visibility preferences.
- Other controls in `⋯`: **About Committed**, **Launch at Login**, **Automatic Updates**, **Check for Updates…**, **Disconnect GitHub**, and **Quit**. **About Committed** explains how contributions are counted.

## How it works

The single metric comes from one GitHub source, computed for the selected trailing window:

- **Contributions** — the app reads the public `github.com/users/<name>/contributions` page anonymously, even when GitHub is connected. It sums the daily counts for the selected window locally. Private activity contributes to this public count only when the person has enabled GitHub’s private-contribution visibility setting.

The app saves the people list and loaded counts locally, so relaunches can show saved numbers while new data loads. Rows distinguish loading, cached data, and failed requests. A person with no contribution data shows a placeholder rather than a zero count.

The popover uses native SwiftUI material for a translucent background. It uses an opaque background when Reduce Transparency or increased contrast is enabled.

## Distribution

Committed is a **Developer ID-signed, notarized** app available through a public download. It requires **macOS 26 or later**, supports **Apple silicon and Intel Macs**, and requires a **GitHub account**.

**[Download Committed for Mac](https://github.com/prompthunt/commit-standings-releases/releases/latest/download/Committed.dmg)**

The Windows app requires **Windows 11**. Download the per-user, unsigned
**[Windows installer](https://github.com/prompthunt/commit-standings-releases/releases/latest/download/Committed-Setup.exe)**.
If SmartScreen appears, choose **More info → Run anyway**. The x64 build runs on
ARM PCs through emulation. Click its notification-area icon to toggle the board;
clicking elsewhere hides it. Connect GitHub and People use standalone windows.
The board follows the system theme, stays opaque, and respects high contrast.
GitHub tokens are stored in **Windows Credential Manager**; visibility choices
stay local to each PC and GitHub account. Use Installed apps to uninstall.

Both platforms share one version and one GitHub Release. Windows uses Tauri's
signed updater with a dedicated key. Automatic Updates downloads in the
background and offers a restart, or installs on Quit. Check for Updates works
with Automatic Updates off. The Mac continues to use Sparkle.

The permanent link points to the latest installer. To install:

1. Open **Committed.dmg**.
2. Drag **Committed** to **Applications**.
3. Launch it from Applications, find it in the menu bar, and connect GitHub.

No TestFlight, App Store, or invitation is required. Releases are hosted in the public GitHub repo `prompthunt/commit-standings-releases`. A landing page can use the same permanent download link.

Installed copies use **Sparkle** for updates. With automatic updates enabled, the app checks periodically, downloads updates in the background, and installs them when Committed quits. **Automatic Updates** controls background downloads; **Check for Updates…** remains available for manual checks. A menu-bar dot and an in-app banner signal a pending update.

The app is intentionally **not sandboxed** to support its Sparkle update path. Bundle and target names remain `CommitStandings` / `com.digg.commitstandings` for update continuity; the product name is **Committed**.

## What it doesn't do today

- **No shared/team board or settings sync.** Each person has their own leaderboard. Connecting the same GitHub account on another Mac derives the same accessible people from GitHub, but visibility preferences remain local. A shared backend is an exploration, not a current feature.
- **Public contribution graph only.** Private activity is included only if the person enables **Contribution settings → Private contributions** on their GitHub profile. A dismissible board tip explains this; the guidance remains available in **About Committed**. Connecting requests `read:org read:user` to load profile and organization membership information. It does not request `repo` access or read repository contents.
- **Desktop only.** The leaderboard lives in the Mac menu bar or Windows notification area. Standalone windows cover connecting GitHub, People, and the contributions explanation. There is no iOS or web app.

## Glossary

| Term | Meaning |
|---|---|
| Competitor | You, someone you follow on GitHub, or a member of your GitHub organizations. Hidden competitors stay in People but leave the leaderboard. |
| Connect GitHub | Authorizing Committed's read-only GitHub access (`read:user read:org`) through GitHub's device flow. It does not create a Committed account; the token stays in the Mac's Keychain or Windows Credential Manager and is sent only to GitHub. Say "Connect GitHub" and "Disconnect GitHub", not "sign in", "sign up", "log out", or "create an account". |
| Window | The trailing time range the board is computed over: Today, 7 days, or 30 days. |
| Contributions | The count behind GitHub's contribution graph ("green squares") for the window. The single ranking metric. |
| Refresh | Reloading contribution counts on a ~5-minute timer, stale menu-open, or stale window switch. Manual **Refresh** also reloads the people list. |
