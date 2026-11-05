# Committed

Committed puts a friendly GitHub leaderboard in your Mac’s menu bar, your Windows tray, or an iPhone app.

For contributors, designers, and agents. Last reviewed: 2026-10-23. Positioning and voice guidance live in [Product Marketing Context](.agents/product-marketing.md).

## What it is

Committed is a Mac **menu-bar app**, a Windows **tray app**, and an **iPhone app** for comparing GitHub contributions with friends. Connect GitHub to load the people you follow and members of your GitHub organizations, then hide anyone you don't want on your board.

Open the menu bar to see where you stand today or over the last 7 or 30 days. Your rank follows the contribution count on your GitHub profile.

## Who it's for

- **Primarily:** developers on Macs, Windows PCs, or iPhones who enjoy friendly competition and want to see how their GitHub contributions compare with friends and people they follow.
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

- **Connect GitHub** runs in a standalone setup window that stays open during the browser hand-off. The app shows a code, you approve it on GitHub, and the token is stored in the Mac's Keychain or Windows Credential Manager. There is no Committed account: connecting authorizes the app's read-only GitHub access on that computer, and **Disconnect GitHub** deletes the token.
- After approval, you go directly to the board while your people load. It includes you, accessible members of your GitHub organizations, and people **you** follow. It does not crawl teammates’ following lists.
- Each username appears once on the board, even when you share multiple connections. The people list syncs when you connect or first open the board, then about every 15 minutes during background refreshes. Manual **Refresh** forces a sync.
- **People…** opens a native alphabetical list with search and **All / Following / Organizations** filters. Click the eye to hide someone or the eye-slash to show them again. Hidden people stay in the list so you can restore them. You cannot hide yourself; there is no manual add or remove flow.
- The app loads every page of organizations, members, and follows. Only a complete successful fetch replaces the saved people list. Failed requests preserve that list and show a retry message. On Windows, sources that load successfully can still add people when another source fails; saved people and source memberships remain until a complete sync succeeds. A failed later page contributes no partial list from that source. Organizations that GitHub does not expose to the app cannot appear.
- Visibility choices are saved **locally on each computer, per GitHub account**. They survive relaunch, disconnecting and reconnecting, refreshes, and someone leaving and rejoining a source. Hiding someone does not change your GitHub follows or membership. Hidden people are excluded from rankings, contribution refreshes, and crossing notifications.
- When upgrading from the old manual list, the first successful sync saves a local backup (`competitors.manual-backup.v1`). People you still follow or share an organization with retain their cached counts and row identities. People outside those sources leave the active board. Disconnecting clears the active account cache but keeps its visibility preferences.
- Other controls in `⋯`: **About Committed**, **Launch at Login**, **Automatic Updates**, **Check for Updates…**, **Disconnect GitHub**, and **Quit**. **About Committed** explains how contributions are counted.

### On iPhone

Committed for iPhone has three tabs: **Board**, **People**, and **Settings**. It shares the Mac app's core code, so ranking, Connect GitHub, People filtering, and visibility rules behave the same.

- **Board** shows your summary, the **Today / 7 days / 30 days** switch, and the ranked board. Pull down to refresh people and Contributions.
- **People** lists everyone alphabetically with search and **All / Following / Organizations** filters. Tap the eye to hide someone or the eye-slash to show them again; the board updates right away. Hidden people stay listed, and you cannot hide yourself. Visibility choices are saved on that iPhone per GitHub account.
- **Settings** has **Leaderboard Notifications** (iOS asks for permission when you turn it on; crossings are checked whenever the app refreshes while open), **About Committed**, and **Disconnect GitHub**, which deletes the token from the iPhone's Keychain and returns to Connect GitHub. Launch at Login, updates, and Quit are Mac-only.

### Live rank (iPhone)

Live rank keeps your current rank in the Dynamic Island and on the Lock Screen as a Live Activity.

- **Compact Dynamic Island:** your rank (for example `#2`) with the trophy glyph, and your Contributions.
- **Minimal Dynamic Island:** your rank.
- **Expanded Dynamic Island:** you between the people ranked directly above and below you, with what it takes to move up ("3 to pass alice").
- **Lock Screen:** the same, plus the Window and how long ago the numbers updated.
- With no visible rivals, Live rank shows your Contributions without a rank. Before your numbers load, it shows placeholders, never zero.
- Twenty minutes after its data, Live rank looks stale: the numbers dim and the refresh age shows, so an old rank never reads as current.
- Tapping Live rank opens the board on Live rank's Window.
- **Settings ▸ Live rank** has an on/off switch and the Window it follows (**Today** by default; the board keeps its own Window). If Live Activities are off for Committed in iOS Settings, it says so and links there. With the Committed relay, Live rank is off until you accept the relay disclosure (below); without it, Live rank is on unless you turn it off.
- Live rank starts when the app is open after Connect GitHub. It updates after every refresh: in the foreground, on the 5-minute timer, and through iOS background app refresh. It updates only when what it shows changed. Hiding or showing someone updates it right away. Changing its Window ends the activity and starts a new one. Disconnect GitHub or turning Live rank off ends it. Only one Live rank activity exists; leftovers are ended on launch.
- On-device limits: iOS ends a Live Activity after 8 hours and doesn't let an app start one from the background. Background app refresh runs only when iOS chooses. Without the relay, Live rank restarts the next time you open the app.

#### Always on with the Committed relay

The **Committed relay** is a small push service that keeps Live rank current while the app is closed. Builds that have a relay configured use it; builds without one keep the on-device behavior above, send nothing anywhere, and never show the disclosure.

- **Disclosure first.** Before Live rank first turns on, one sheet explains that the relay receives your GitHub username and the usernames on your board (public data), your Live rank Window and time zone, and a push token for Live rank on that iPhone, and that it never receives your GitHub token. It appears once your board has loaded after Connect GitHub, and again from the Settings switch until you accept it. **Turn On Live rank** accepts; **Not Now** leaves Live rank off, and the app doesn't ask again on its own.
- **What the relay stores per iPhone:** a random install ID, a hash of a random install secret (the secret stays in the iPhone's Keychain), the APNs environment, push tokens for starting and updating Live rank, your login, the visible logins on your board in board order, the Window, and the time zone. Hidden people are not sent. The GitHub token never leaves the iPhone except to GitHub.
- **Always on.** Every 5 minutes the relay reads the same public contribution pages as the apps, recomputes your rank with the same rules, and updates Live rank when it changed, so a pass shows within about 5 minutes with the app closed. Today is counted for your local day. Before iOS's 8-hour limit the relay ends the activity and starts a fresh one. If you dismiss Live rank, the relay waits until its next rotation (at most 7.5 hours) before starting it again.
- **Kept in step.** The app updates its registration when you hide or show someone, change Live rank's Window, when a people sync changes your board, when your time zone changes, and when iOS issues new push tokens. Activities the relay started are reported back so it can update them.
- **Removal.** Turning Live rank off or **Disconnect GitHub** deletes the iPhone's registration and ends Live rank. If the relay can't be reached, the app retries until it succeeds.
- The relay doesn't send Leaderboard Notifications; those stay on the device.

## How it works

The single metric comes from one GitHub source, computed for the selected trailing window:

- **Contributions** — the app reads the public `github.com/users/<name>/contributions` page anonymously, even when GitHub is connected. It sums the daily counts for the selected window locally. Private activity contributes to this public count only when the person has enabled GitHub’s private-contribution visibility setting.

The app saves the people list and loaded counts locally, so relaunches can show saved numbers while new data loads. Rows distinguish loading, cached data, and failed requests. A person with no contribution data shows a placeholder rather than a zero count.

The popover uses native SwiftUI material for a translucent background. It uses an opaque background when Reduce Transparency or increased contrast is enabled.

## Distribution

The Mac app is **Developer ID-signed and notarized**, available through a public download. It requires **macOS 26 or later**, supports **Apple silicon and Intel Macs**, and requires a **GitHub account**.

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

- **No shared/team board or settings sync.** Each person has their own leaderboard. Connecting the same GitHub account on another Mac derives the same accessible people from GitHub, but visibility preferences remain local. There is no Committed account or shared backend. The only server is the Committed relay, which keeps an iPhone's Live rank current and holds just the public logins it needs, never a GitHub token.
- **Public contribution graph only.** Private activity is included only if the person enables **Contribution settings → Private contributions** on their GitHub profile. A dismissible board tip explains this; the guidance remains available in **About Committed**. Connecting requests `read:org read:user` to load profile and organization membership information. It does not request `repo` access or read repository contents.
- **No web or Android app.** The leaderboard lives in the Mac menu bar, the Windows notification area, and the iPhone app. On desktop, standalone windows cover connecting GitHub, People, and the contributions explanation.

## Glossary

| Term | Meaning |
|---|---|
| Competitor | You, someone you follow on GitHub, or a member of your GitHub organizations. Hidden competitors stay in People but leave the leaderboard. |
| Connect GitHub | Authorizing Committed's read-only GitHub access (`read:user read:org`) through GitHub's device flow. It does not create a Committed account; the token stays in the Mac's Keychain, Windows Credential Manager, or the iPhone's Keychain and is sent only to GitHub (never to the Committed relay). Say "Connect GitHub" and "Disconnect GitHub", not "sign in", "sign up", "log out", or "create an account". |
| Window | The trailing time range the board is computed over: Today, 7 days, or 30 days. |
| Contributions | The count behind GitHub's contribution graph ("green squares") for the window. The single ranking metric. |
| Live rank | The iPhone Live Activity that keeps your rank for one Window in the Dynamic Island and on the Lock Screen. It follows the same visible people and ranking as the board. |
| Committed relay | The push service that keeps Live rank current while the iPhone app is closed. It receives your GitHub username, the visible usernames on your board, your Live rank Window and time zone, and push tokens, all after a one-time disclosure. It never receives a GitHub token. Say "the Committed relay" or "the relay", not "the server", "the backend", or "sync". |
| Refresh | Reloading contribution counts on a ~5-minute timer, stale menu-open, or stale window switch. Manual **Refresh** also reloads the people list. |
