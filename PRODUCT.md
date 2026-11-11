# Committed

Committed puts a friendly GitHub leaderboard in your Mac’s menu bar, your Windows tray, or an iPhone app.

For contributors, designers, and agents. Last reviewed: 2026-11-04. Positioning and voice guidance live in [Product Marketing Context](.agents/product-marketing.md).

## What it is

Committed is a Mac **menu-bar app**, a Windows **tray app**, and an **iPhone app** for comparing GitHub contributions with friends. Connect GitHub to load the people you follow and members of your GitHub organizations, then hide anyone you don't want on your board.

Open the menu bar (or the app on iPhone) to see where you stand today, over the last 7 or 30 days, or so far this month. Your rank follows the contribution count on your GitHub profile.

## Who it's for

- **Primarily:** developers on Macs, Windows PCs, or iPhones who enjoy friendly competition and want to see how their GitHub contributions compare with friends and people they follow.
- **Also:** teammates who want that same friendly competition with people in their GitHub organizations.

Each user gets a personal board based on their GitHub connections. Friends do not need to install Committed to appear on it; their counts come from their public GitHub contribution graphs.

The leaderboard compares activity counts. It does not assess code quality or work performance.

## Core loop

1. Connect GitHub and let your people load automatically.
2. Open the menu bar to compare contributions for Today, 7 days, 30 days, or This month.
3. Check back as the board refreshes, or turn on notifications to hear when you pass someone or they pass you.

## What it does

Clicking the menu-bar icon opens a popover with your contribution summary and a ranked leaderboard. Each row is a person you've kept visible on your board:

- **Rank + avatar + username** — pulled from real GitHub avatars; your own row is marked with a **"you"** badge.
- **Contributions** — the single ranking metric: the GitHub contribution-graph "green squares" count for the selected window. Rows are sorted by contributions, highest first.
- **Your summary** — your avatar, name or handle, contribution count, and streak appear above the list. Your rank also appears in the menu bar when you have visible rivals.
- **Streaks** — "🔥 12" beside a count is that person's streak: 12 days in a row with at least one contribution. It stays alive through today until today ends, so having no contributions yet this morning doesn't break it. It shows from 2 days, reads "365+" past GitHub's calendar (about a year), and VoiceOver reads it as "12-day streak". A count that failed or hasn't loaded shows no streak, never "0".
- **Today's movement** — small chevrons show rank changes since the first refresh of the day. Hiding or showing people starts a new movement baseline.
- **Leaderboard Notifications** — opt in through `⋯` to receive a notification when someone passes you or you pass them, and when a month ends ("October final: You finished #3 of 8").

### Time windows

A segmented control at the top switches the window; the contribution count recomputes for it:

- **Today** — the current day.
- **7 days** — the trailing 7 days.
- **30 days** — the trailing 30 days.
- **This month** — your local calendar month so far (Mac and iPhone; Windows doesn't have it yet). It resets to zero for everyone at local midnight on the 1st. Beside it, the board says which day of the month it is ("Day 10 of 30"): on the Mac under your count, on iPhone in your summary's heading. Today's movement chevrons work on it as on Today: each person's places moved since the day's first This month ranking.

Every window is available once the contribution data loads; there is no history-building or backfill period. The app sums the daily counts for the selected range, in the device's time zone. Choosing 30 days is saved as it always was, so existing settings are unaffected.

### Final standings and medals

When a month ends, its **Final standings** are last month's ranks among the people currently on your board, worked out from each person's GitHub calendar with the board's own ranking (you win ties). The top three earn a **medal**, 🥇 gold, 🥈 silver and 🥉 bronze, when their total for the month was above zero. Someone whose calendar hasn't loaded ranks last with no medal.

- **On the 1st** the board (Mac popover and iPhone Board) opens on last month's Final standings for the whole day, behind a **🏅 October final standings** switch, with "October final · You finished #2 of 6" over the rows and the medal before each winner's name. Picking a Window, or the switch, returns to the live board; the next 1st opens on the new month's. On the Mac your summary shows your total for that month while they're up.
- **Recomputed, not frozen.** Hiding or showing someone changes past months' Final standings the same way it changes the board. Months before your own calendar's first full month aren't offered.
- **Notification.** The first successful refresh after a month ends sends one Leaderboard Notification, "October final" / "You finished #3 of 8", only when Leaderboard Notifications are on. Each month is announced once per account on each device; it counts as announced even with notifications off, so switching them on later doesn't bring up old news. It waits while someone with a saved calendar fails to refresh, so it never reports a place from stale numbers. The Committed relay doesn't send it: on iPhone it comes when the app next refreshes, including background app refresh.
- **Sample board** shows the same, from its made-up calendars.

### Refresh behavior the user notices

- The board **refreshes itself** in the background about every 5 minutes.
- Opening the menu refreshes only if the data is stale (older than ~2 minutes), so re-opening doesn't constantly flash "updating".
- Switching windows shows cached numbers instantly and only fetches when that window's data is stale or missing.
- **Refresh** in the `⋯` menu reloads both the GitHub people list and contribution counts.
- During a refresh, cached values remain visible and **pulse** gently. The first load uses placeholders and a "Fetching the first set of standings" message.
- People-sync status appears on the board and in **People…**. The contribution refresh age appears beside **Refresh** in the `⋯` menu.

### Connecting GitHub and managing people

- **Connect GitHub** runs in a standalone setup window that stays open during the browser hand-off. The app shows a code, you approve it on GitHub, and the token is stored in the Mac's Keychain or Windows Credential Manager. There is no Committed account: connecting authorizes the app's read-only GitHub access on that device, and **Disconnect GitHub** deletes the token.
- After approval, you go directly to the board while your people load. It includes you, accessible members of your GitHub organizations, and people **you** follow. It does not crawl teammates’ following lists.
- Each username appears once on the board, even when you share multiple connections. The people list syncs when you connect or first open the board, then about every 15 minutes during background refreshes. Manual **Refresh** forces a sync.
- **People…** opens a native alphabetical list with search and **All / Following / Organizations** filters. Click the eye to hide someone or the eye-slash to show them again. Hidden people stay in the list so you can restore them. You cannot hide yourself; there is no manual add or remove flow.
- The app loads every page of organizations, members, and follows. Only a complete successful fetch replaces the saved people list. Failed requests preserve that list and show a retry message. On Windows, sources that load successfully can still add people when another source fails; saved people and source memberships remain until a complete sync succeeds. A failed later page contributes no partial list from that source. Organizations that GitHub does not expose to the app cannot appear. An organization that won't list its members for Committed (it restricts third-party app access or enforces SAML single sign-on, so GitHub answers 403 every time) is left out rather than failing the sync, so you and the people you follow still load; the sync status names it and says an organization owner can approve Committed. A 403 that's really a rate limit fails the sync like any other temporary error.
- Visibility choices are saved **locally on each computer or iPhone, per GitHub account**. They survive relaunch, disconnecting and reconnecting, refreshes, and someone leaving and rejoining a source. Hiding someone does not change your GitHub follows or membership. Hidden people are excluded from rankings, contribution refreshes, and crossing notifications.
- When upgrading from the old manual list, the first successful sync saves a local backup (`competitors.manual-backup.v1`). People you still follow or share an organization with retain their cached counts and row identities. People outside those sources leave the active board. Disconnecting clears the active account cache but keeps its visibility preferences.
- Other controls in `⋯`: **About Committed**, **Launch at Login**, **Automatic Updates**, **Check for Updates…**, **Disconnect GitHub**, and **Quit**. **About Committed** explains how contributions are counted.

### On iPhone

Committed for iPhone runs the same board, ranking, people sync, and visibility rules as the Mac app. It's a native app with three tabs: **Board**, **People**, and **Settings**. On iPhone Duo the tabs and toolbar sit in the vertical side bar. It's dark only and wears the website's look: an ink background, lime for you and your rank, Inter Tight numbers, and a lit field of contribution squares behind your rank.

- **Board** — your summary (your rank, Contributions, your streak, today's movement, the gap to pass the person ahead, and when the numbers were updated), the **Today / 7 days / 30 days / This month** switch (a menu at the largest text sizes), and everyone ranked with the same rows as the Mac popover, including the "you" badge, placeholders, today's movement, streaks, and the private-contributions tip. Pull to refresh reloads people and contributions. Opening the app refreshes only when the data is older than about 2 minutes; while open, the board refreshes about every 5 minutes.
- **Share board** — the share button in the Board's navigation bar opens a sheet for sharing the board as an image of Committed's own widget. Swipe between **Board** (the large widget, grown to eight people on a square and ten on a story, counting you: you sit below a rule when you're further down), **Your race** (the medium widget), **Rank** (the small widget), and **Top 4** (the Committed Board widget). Pick **Square** (1080 × 1080) or **Story** (1080 × 1920: the widget on the contribution-square field under "Who shipped more today?", "…this week?", "…in 30 days?" or "…this month?"). The image shows the Board's current Window and only the people the board shows, with when the numbers are from ("As of Nov 8, 2026 at 1:22 PM") under the widget and "Committed · 27 people" and gitcommitted.app at the foot. **Share** opens the system share sheet with the image alone as a PNG, with no caption. On the 1st, while the Board offers last month's Final standings, the sheet also offers **Final standings** first (and opens on it while the Board shows them): the large widget's rows with 🥇🥈🥉 before the top three names under "October final", "Who shipped more in October?" on a story, and "Final · October 2026" under the widget instead of a timestamp.
- **iPhone Duo** — open in landscape, the Board shows two panes divided evenly at the fold: the leaderboard on the leading side and your summary beside it, with the people directly above and below you under it. Wherever there's room for only one (closed, open in portrait, Split View), the leaderboard shows with your summary at the top. Opening and closing keeps the tab and the Window. Centered controls (Connect GitHub, the People filter) move to one side of the fold when it's partially folded like a book.
- **Connect GitHub** uses the same device flow. The code is shown large with **Copy Code** and **Open GitHub**, and approval can happen in Safari on the same phone. The token is stored in the iPhone's Keychain.
- **Sample board** — **Try a sample board**, under Connect GitHub, opens the real app on built-in sample data: five people ranked across every Window with made-up streaks, People with its filters and hide/show, Share board, Live rank (on the phone only, see below), the Home Screen, Lock Screen and Committed Board widgets, and Leaderboard Notifications as on a real board. Pull to refresh moves a count and shows a movement chevron. Nothing leaves the iPhone: no GitHub API calls, avatars as initials (in the app, Share board, Live rank and the widgets, never a saved avatar), and no Committed relay. A slim **Sample board · Connect GitHub** banner tops the Board and People; tapping it starts Connect GitHub. Reopening the app returns to the Sample board. Connect GitHub from the Sample board (the banner or Settings) shows GitHub's code over it, with **Cancel**, while the Sample board stays underneath. Only a successful Connect GitHub replaces it, completely, with no sample people or visibility preferences left behind. A declined or expired code keeps the Sample board: the cover says why, with **Try Again**, and Cancel returns to the Sample board. Cancel while waiting returns to it too, with no error. While Connect GitHub is waiting for approval, the Sample board can't be started or left.
- **People** — everyone alphabetically, with search and **All / Following / Organizations** filters that match the Mac's **People…** window, and when people last synced from GitHub. Tap the eye to hide someone or the eye-slash to show them again. Hidden people stay listed; you can't hide yourself. The board and rankings update right away.
- **Settings** — **Live rank** (see below), **Leaderboard Notifications** (turning it on shows the iOS permission prompt; it switches back off if permission is denied, and links to iOS Settings when notifications are off there), **About Committed** (how contributions are counted, and the version), and **Disconnect GitHub**, which deletes the token from the Keychain, ends Live rank, clears the active account cache, keeps visibility preferences, and returns to Connect GitHub. On the Sample board, **Connect GitHub** and **Leave Sample Board** take its place, at the top of Settings; leaving ends the Sample board's Live rank, resets the widgets to Connect GitHub, forgets its people and hides, and returns to Connect GitHub.
- Crossing notifications use the same copy as the Mac and fire from refreshes while the app is open, shown as a banner even when Committed is in front.
- Mac-only items don't exist on iPhone: **Launch at Login**, **Automatic Updates**, **Check for Updates…**, and **Quit**.

### Live rank on iPhone

**Live rank** is a Live Activity that keeps your current rank in the Dynamic Island and on the Lock Screen.

- **Compact Dynamic Island:** the trophy with your rank (for example `#2`) on one side and your Contributions on the other. **Minimal** (when another app's activity shares the island): your rank.
- **Expanded Dynamic Island:** the person ranked directly above you, you, and the person directly below, in the board's own rows (rank, avatar, username, the **you** badge, today's movement chevron, Contributions, and the squares glyph), with the Window ("Today") beside the trophy and, on the right, how long ago the numbers were updated ("13 min, 36 sec"), counting up every second.
- **Lock Screen:** the trophy and the Window with the same counting-up age on the right, then the same three rows.
- Avatars in Live rank are small copies the app saves for everyone on the board each time it refreshes; someone whose avatar hasn't been saved yet shows initials.
- With no visible rivals, Live rank shows your Contributions without a rank rather than `#1 of 1`, and the Lock Screen says "Just you so far", with your streak beside your count (on the Lock Screen) or beside "Just you so far" (in the expanded island). Before your count loads it shows placeholders, never zero, and the Lock Screen says "Waiting for your first count". Twenty minutes after its data, Live rank's colors step down (the lit squares behind a Lock Screen without rows go dark); the compact island, which has no room for the age, shows a clock beside your count.
- The expanded island and the Lock Screen show streaks ("🔥 12") on the rows, yours and the people above and below you, as the Board does; the compact and minimal island don't.
- Tapping Live rank opens the Board on Live rank's Window.
- **Settings ▸ Live rank** has an on/off switch, a Window picker (Today, 7 days, 30 days or This month; Today by default, independent of the board's Window), and a status line. When Live Activities are off for Committed in iOS Settings, it says so and links there.
- Live rank starts while the app is open, once you've connected GitHub and your board loads. It updates whenever the app refreshes: in the foreground, on pull-to-refresh, and during background app refresh, which iOS schedules when it chooses. It only updates when what it shows has changed. Hiding or showing someone, or changing Live rank's Window, updates it right away while the app is open. A Window change ends the activity and starts a new one.
- **Disconnect GitHub** and turning Live rank off end it. Only one Live rank shows at a time; extra copies end the next time the app opens.
- **With the Committed relay** (below), Live rank stays on all day with the app closed. The relay recomputes your rank and the streaks Live rank shows every 5 minutes from public contribution graphs, in your time zone's days, and updates Live rank within about 5 minutes of a change. iOS ends a Live Activity after 8 hours, so the relay replaces it with a fresh one at 7.5 hours. If you dismiss Live rank, the relay brings it back at the next 7.5-hour point rather than every 5 minutes. Today resets at your local midnight, and This month at your local midnight on the 1st. On This month, as on Today, Live rank shows movement since the day's first ranking. If the relay is older than This month and can't rank it, Live rank on This month updates when Committed refreshes, as without the relay, and Settings says so.
- **The first time Live rank turns on with the relay** (after Connect GitHub, or from the switch), one sheet explains what the relay receives. **Turn On Live Rank** starts it; **Not Now** leaves it off until you turn the switch on, which shows the sheet again. Once accepted, it isn't shown again.
- **Without the relay** (a build with no relay configured), Live rank is on by default and driven by the iPhone alone: iOS ends it after 8 hours, the app can't start one from the background, so it comes back the next time you open Committed, and updates while the app is closed depend on background app refresh.
- **On the Sample board**, Live rank always runs as it does without the relay, whatever the build: it never registers with the Committed relay, the relay sheet never appears, and its settings aren't saved. Leaving the Sample board ends it.

### Widgets

Committed's widgets show Live rank's Window: **Committed** (small, medium and large on the Home Screen; rectangular, inline and circular on the Lock Screen; the small size also shows in CarPlay and StandBy) and **Committed Board** (a small list made for StandBy).

- **Every Home Screen size** is headed by the trophy and the Window ("Today", "7 days", "30 days", "This month"), with how long ago the numbers were updated ("13 min, 36 sec") counting up every second on the right. The small sizes put the age on its own line. The medium widget shows the person above you, you and the person below in the board's rows; the large widget shows the top six, with you below a rule when you're further down; the small widget shows your rank and count, with your streak beside the count. Rows on the medium and large widgets show streaks as the Board does; the Committed Board widget's narrow rows don't. The rectangular Lock Screen widget shows "#3 · 12 today" over the age; the inline one shows "#3 · 12 today".
- **Updates:** the app updates the widgets whenever it refreshes. Between those, the widgets refresh themselves every 15 minutes: they re-read everyone's public contribution graph anonymously, as the app does (no token, no Committed relay), re-rank the board the app last saved, carry today's movement on, and work out everyone's streak from the graphs they just read. iOS spends widget updates from a daily budget, so it can stretch 15 minutes to 30 or more; the counting-up age shows exactly how old the numbers are. Someone GitHub doesn't answer for keeps their last count (on Today, until midnight; on This month, until the 1st) and their streak until midnight; after that their row shows no streak until GitHub answers. A widget an hour past its data steps its colors down; the age stays grey, since its value already says how old the numbers are.
- **The Sample board's** widgets never fetch: they show what the Sample board saved.
- **Share board** images use the same widgets without the counting-up age; the timestamp under the widget says when the numbers are from.

### The Committed relay

The **Committed relay** is a small push service that keeps Live rank current while the iPhone app is closed. It's the only server Committed uses, and it exists only for Live rank.

- **What it receives:** your GitHub username, the usernames on your board (visible people, in board order), Live rank's Window, your time zone, whether the build pushes through Apple's sandbox or production service, and the Apple push tokens for Live rank on that iPhone. Registration uses a random installation ID and secret kept in the iPhone's Keychain. There is no Committed account.
- **What it never receives:** your GitHub token, which is sent only to GitHub. The relay reads the same public contribution pages as the apps, anonymously.
- **When the iPhone updates it:** when you hide or show someone, change Live rank's Window, when a people sync changes who's on your board, when your time zone changes, and when Apple issues a new push token.
- **Turning Live rank off or Disconnect GitHub** deletes the iPhone's registration and ends Live rank.
- Crossing notifications still come only from the device; the relay sends Live rank updates, not notifications.

## How it works

The single metric comes from one GitHub source, computed for the selected window:

- **Contributions** — the app reads the public `github.com/users/<name>/contributions` page anonymously, even when GitHub is connected. It sums the daily counts for the selected window locally. Private activity contributes to this public count only when the person has enabled GitHub’s private-contribution visibility setting.

The app saves the people list and loaded counts locally, so relaunches can show saved numbers while new data loads. Rows distinguish loading, cached data, and failed requests. A person with no contribution data shows a placeholder rather than a zero count.

The popover uses native SwiftUI material for a translucent background. It uses an opaque background when Reduce Transparency or increased contrast is enabled.

## Distribution

The Mac app is **Developer ID-signed and notarized**, available through a public download. It requires **macOS 26 or later**, supports **Apple silicon and Intel Macs**, and requires a **GitHub account**.

Committed for iPhone requires **iOS 27.1 or later** and isn't publicly distributed yet; TestFlight comes first.

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

- **No shared/team board or settings sync.** Each person has their own leaderboard. Connecting the same GitHub account on another Mac, PC, or iPhone derives the same accessible people from GitHub, but visibility preferences remain local. The only server is the **Committed relay**, which holds just what Live rank needs on one iPhone (public usernames, Window, time zone, push tokens); it doesn't sync boards or settings.
- **Public contribution graph only.** Private activity is included only if the person enables **Contribution settings → Private contributions** on their GitHub profile. A dismissible board tip explains this; the guidance remains available in **About Committed**. Connecting requests `read:org read:user` to load profile and organization membership information. It does not request `repo` access or read repository contents.
- **No web app.** The leaderboard lives in the Mac menu bar, the Windows notification area, and the iPhone app. On desktop, standalone windows cover connecting GitHub, People, and the contributions explanation; on iPhone they are tabs and screens in the app.

## Glossary

| Term | Meaning |
|---|---|
| Competitor | You, someone you follow on GitHub, or a member of your GitHub organizations. Hidden competitors stay in People but leave the leaderboard. |
| Connect GitHub | Authorizing Committed's read-only GitHub access (`read:user read:org`) through GitHub's device flow. It does not create a Committed account; the token stays in the Mac's or iPhone's Keychain or Windows Credential Manager and is sent only to GitHub, never to the Committed relay. Say "Connect GitHub" and "Disconnect GitHub", not "sign in", "sign up", "log out", or "create an account". |
| Window | The time range the board is computed over: Today, 7 days, 30 days (trailing), or This month. |
| This month | A Window for the calendar month to date, in the device's time zone. It resets to zero on the 1st. Say "This month", not "monthly" or "30 days" (a different, trailing Window). |
| Final standings | A finished month's ranks among the people currently on your board, recomputed from GitHub's calendar (you win ties), not frozen. Shown on the board all day on the 1st. Say "Final standings", not "results" or "archive". |
| Medal | Gold, silver or bronze for ranks 1 to 3 of a finished month's Final standings, only for a total above zero. |
| Contributions | The count behind GitHub's contribution graph ("green squares") for the window. The single ranking metric. |
| Streak | Consecutive days with at least one contribution, alive through today: a day with none yet doesn't end it until the day is over. Days are your device's, as for Today. Shown as "🔥 12" from 2 days, "365+" past GitHub's calendar. |
| Refresh | Reloading contribution counts on a ~5-minute timer, stale menu-open, or stale window switch. Manual **Refresh** also reloads the people list. |
| Live rank | The Live Activity that shows your current rank, your Contributions, and the people just above and below you in the Dynamic Island and on the Lock Screen, for a Window you choose in Settings. Say "Live rank", not "widget" or "Live Activity" in product copy. |
| Committed relay | The push service that keeps Live rank current with the iPhone app closed. It receives public GitHub usernames, Live rank's Window, the time zone, and Apple push tokens, never the GitHub token. Say "Committed relay" or "the relay", not "server", "backend", or "sync". |
| Sample board | Committed running on built-in sample data instead of a connected GitHub account, opened with **Try a sample board** on the Connect GitHub screen. Everything works on it, and nothing leaves the device. Say "sample board", never "demo account", "guest", or "sign in". |
