# App Store listing

The App Store listing for Committed for iPhone ("Committed: Commit Leaderboard", app
`6831797452`, version 1.0.2, en-US). Change it here in a PR, then re-apply it.

## What's here

`metadata/` is an `asc metadata` tree:

| File | Holds |
|---|---|
| `app-info/en-US.json` | Name, subtitle, privacy policy URL |
| `version/1.0.2/en-US.json` | Description, keywords, promotional text, What's New, support and marketing URLs |
| `categories.json` | Developer Tools, with Productivity as the secondary |
| `age-rating.json` | Every answer none or false (4+) |
| `review-information.json` | App Review notes; no demo account |

[`scripts/appstore_apply.py`](../scripts/appstore_apply.py) also sets what `asc metadata`
doesn't cover:

- copyright: "2026 Prompt Hunt, Inc."
- content rights: uses third-party content (GitHub usernames and avatars)
- price: Free
- availability: every territory, and new ones automatically
- release type: after approval (Apple releases each version as soon as it's approved), with no phased release

The App Review contact isn't in the repo. The script copies it from the app's TestFlight beta
review details in App Store Connect.

## Re-apply

```bash
python3 scripts/appstore_apply.py --dry-run   # show what would change
python3 scripts/appstore_apply.py             # apply it
```

It needs `asc` signed in with the Prompt Hunt API key (`asc auth status`). Each step reads App
Store Connect first and writes only what differs, so a second run prints "No changes."
Then check the version:

```bash
asc validate --app 6831797452 --version-id <1.0.2's version id> --platform IOS
```

`python3 -m unittest discover -s scripts -p 'test_*.py'` checks the files against Apple's
limits and the glossary before anything reaches App Store Connect.

The script never runs `asc web` (an Apple ID sign-in). If Apple ever refuses a step through the
API, such as first-time availability, the script prints the command or App Store Connect page
to use and exits with status 2.

## App Privacy label

`privacy.json` is the published App Privacy label, in `asc web privacy` format. Apple only
accepts it through an Apple ID web session, so it's applied by hand, not by the script:

```bash
asc web privacy plan    --app 6831797452 --file appstore/privacy.json   # read-only diff
asc web privacy apply   --app 6831797452 --file appstore/privacy.json --allow-deletes --confirm
asc web privacy publish --app 6831797452 --confirm
```

What it declares, all linked to the user, used for App Functionality, and not used for tracking:

| Category | What it covers |
|---|---|
| User ID | The GitHub username and the usernames on the board, sent to the Committed relay for Live rank |
| Device ID | The APNs push tokens and the relay's random installation ID |
| Other Data | The time zone sent to the relay with Live rank's Window (Apple has no time zone category) |

No crash data, analytics or advertising data is collected. If that changes, update this file,
the label and the [privacy policy](https://gitcommitted.app/privacy) together.
