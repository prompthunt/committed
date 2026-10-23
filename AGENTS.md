# Committed — agent & contributor guide

Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup and verification. Product behavior
is documented in [PRODUCT.md](PRODUCT.md). Keep personal machine setup and account
administration notes outside this repository.

macOS menu-bar app (SwiftUI) showing a GitHub-contributions leaderboard among friends.
Distributed as a Developer ID-signed, notarized app that auto-updates via **Sparkle**.

> Naming: the product is **"Committed"**, but the bundle id, Xcode target, Sparkle keys,
> and repos deliberately stay **"CommitStandings"** / `com.digg.commitstandings`. This
> mismatch is intentional — **do not "fix" it**, or you break auto-update continuity.

## Releasing (read before shipping a build)

Releases go to the **public** repo `prompthunt/commit-standings-releases` as a
GitHub Release tagged `v<version>`, with `--latest`.

The source and releases repositories transferred to Prompt Hunt on 2026-10-22.
Keep the former `addisonk/commit-standings` and
`basic-intelligence/commit-standings-releases` locations empty: recreating either
repository removes GitHub's redirects, including URLs used by installed apps.

**Use the script — don't hand-assemble `gh release create`:**

```bash
scripts/publish-release.sh        # packages from the current checkout, publishes, verifies links
```

Do it in this order:

1. **Bump the version first.** Edit `CommitStandings/Info.plist`:
   `CFBundleShortVersionString` (e.g. `0.1.44`) **and** `CFBundleVersion` (build number,
   must increment — Sparkle ignores a release whose build number didn't change).
2. Land the change on `main` (branch → PR → merge). Build the release **from `main`**.
3. Run `scripts/publish-release.sh`. It calls `package-release.sh` (notarize + sign +
   `appcast.xml`), then publishes the release with **all four assets** and verifies the
   public links return 200.

**Every release MUST upload these four assets** (the script enforces it):

| Asset | Why it must be present every time |
|---|---|
| `appcast.xml` | Sparkle feed. `SUFeedURL` = `…/releases/latest/download/appcast.xml`. |
| `CommitStandings-<ver>-<build>-<sha>.app.zip` | Sparkle update payload. |
| `CommitStandings-<ver>-<build>-<sha>.dmg` | Versioned human download. |
| `Committed.dmg` | **Stable-named copy.** The permanent share link `…/releases/latest/download/Committed.dmg` only resolves if an identically-named asset exists on the *current* latest release. Drop it from one release and the link 404s. |

After publishing, confirm (the script does this automatically):
- `…/releases/latest/download/Committed.dmg` → 200
- `…/releases/latest/download/appcast.xml` → 200
- the appcast's `<enclosure url>` is the **per-tag** form `…/releases/download/v<ver>/…` and → 200

## Hard invariants (regressions here have broken updates before)

1. **App stays UN-sandboxed.** No `com.apple.security.app-sandbox` entitlement. Sandboxing
   strips Sparkle's XPC helper entitlements and downloads fail for everyone. Not App Store,
   so sandbox isn't needed.
2. **Appcast enclosure URLs are per-tag, never `latest/download/<versioned-file>`.**
   `latest/download/` only serves the current latest release; once superseded it 404s and
   anyone holding a cached appcast gets "An error occurred while downloading the update."
   `package-release.sh` defaults `APPCAST_DOWNLOAD_URL_PREFIX` to `…/releases/download/v${VERSION}/`.
   `SUFeedURL` itself stays `latest/download/appcast.xml` (always fetch the newest feed).
3. **Appcast must not reference release notes.** A `<sparkle:releaseNotesLink>` to an
   un-uploaded `.app.md` makes Sparkle 404 and abort. The script no longer emits one.
4. **The menu-bar agent must `NSApplication.shared.activate` before showing the updater**
   (`LSUIElement=true` means it never comes forward on its own).
5. **`StandingRow` is the single shared row** for the popover board and the Committed window —
   don't fork row rendering. Board ordering lives in one place: `Ranking.order`.
6. **New Swift files must be added to `CommitStandings.xcodeproj`** (e.g. via the `xcodeproj`
   Ruby gem) or they won't compile. Verify with a build, not just by creating the file.

## Build & test

```bash
xcodebuild -scheme CommitStandings -destination 'platform=macOS' build test
# local packaging smoke test (no notarization / no clean-git requirement):
scripts/package-release.sh --skip-notarization --skip-git-check
```

`git push` to the GitHub remote needs the repo-local `http.version HTTP/1.1` + large
`http.postBuffer` (already configured) or it fails with HTTP 400.
