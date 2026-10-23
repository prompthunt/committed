# Committed

[![Build and test](https://github.com/prompthunt/committed/actions/workflows/ci.yml/badge.svg)](https://github.com/prompthunt/committed/actions/workflows/ci.yml)

A tiny macOS menu-bar app that turns your GitHub contributions into a friendly leaderboard
among friends. See who's shipping, get a nudge when someone passes you (or you pass them),
and watch your spot on the board move through the day.

## Download

**[⬇︎ Download Committed (latest)](https://github.com/prompthunt/commit-standings-releases/releases/latest/download/Committed.dmg)**

That link always points at the newest release. Then:

1. Open the downloaded **Committed.dmg**.
2. Drag **Committed** into your **Applications** folder.
3. Launch it — Committed lives in your menu bar (look for it up top, not in the Dock).

The app is signed with a Developer ID and notarized by Apple, so it opens without security
warnings. It keeps itself up to date automatically — no need to re-download.

Prefer to see all versions and release notes? Browse the
[releases page](https://github.com/prompthunt/commit-standings-releases/releases/latest).

## What it does

- A compact leaderboard of you, your GitHub organization members, and people you follow, ranked by GitHub contributions.
- People sync automatically from GitHub; use **People…** to search, filter by source, and hide or show anyone on your board.
- **Today / 7 days / 30 days** views.
- **Leaderboard Notifications** (opt-in): a ping when a friend passes you, or you pass them.
- Small rank-shift chevrons showing how your placement moved today.

## Website

The marketing site for [gitcommitted.app](https://gitcommitted.app) lives in [`site/`](site/README.md) — a static Next.js app (`cd site && npm install && npm run dev`). It's independent of the Xcode project and release scripts.

## Building it yourself

Source: [prompthunt/committed](https://github.com/prompthunt/committed).
This repository starts from a clean source snapshot. Earlier development history
and internal account records are retained separately and are not part of this repository.
Use macOS 26+ and Xcode 26+. Developer ID signing and notarization credentials are
only needed for official distribution; local builds use ad hoc signing.

```bash
xcodebuild -scheme CommitStandings -configuration Debug \
  -destination 'platform=macOS' CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= build test
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup and pull requests,
[AGENTS.md](AGENTS.md) for release invariants, and [SECURITY.md](SECURITY.md) to
report a vulnerability privately. Official releases keep their existing update feed.

## License

Original project source is [MIT licensed](LICENSE). See
[third-party notices](THIRD_PARTY_NOTICES.md) for fonts, dependencies, and images.
