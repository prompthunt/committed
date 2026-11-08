# App Store listing

The App Store listing for Committed for iPhone ("Committed: Commit Leaderboard", app
`6831797452`, version 1.0, en-US). Change it here in a PR, then re-apply it.

## What's here

`metadata/` is an `asc metadata` tree:

| File | Holds |
|---|---|
| `app-info/en-US.json` | Name, subtitle, privacy policy URL |
| `version/1.0/en-US.json` | Description, keywords, promotional text, support and marketing URLs |
| `categories.json` | Developer Tools, with Productivity as the secondary |
| `age-rating.json` | Every answer none or false (4+) |
| `review-information.json` | App Review notes; no demo account |

[`scripts/appstore_apply.py`](../scripts/appstore_apply.py) also sets what `asc metadata`
doesn't cover:

- copyright: "2026 Prompt Hunt, Inc."
- content rights: uses third-party content (GitHub usernames and avatars)
- price: Free
- availability: every territory, and new ones automatically
- release type: manual, with no phased release

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
asc validate --app 6831797452 --version-id efad017c-5171-480c-b19e-f9c3548e521d --platform IOS
```

`python3 -m unittest discover -s scripts -p 'test_*.py'` checks the files against Apple's
limits and the glossary before anything reaches App Store Connect.

The script never runs `asc web` (an Apple ID sign-in). If Apple ever refuses a step through the
API, such as first-time availability, the script prints the command or App Store Connect page
to use and exits with status 2. The App Privacy label works only that way; see spec #65.
