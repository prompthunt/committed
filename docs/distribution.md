# Distributing Committed

Committed ships a Mac menu-bar app and a Windows tray app. The Mac build is distributed as a signed, notarized DMG with the app and an Applications shortcut inside. Windows uses an unsigned per-user NSIS installer prepared in CI.

The local Debug workflow is intentionally separate. The release script passes signing, bundle ID, and deployment overrides at package time instead of changing how Debug launches from Xcode.

## Requirements

- Apple Developer Program membership.
- Xcode installed and selected with `xcode-select`.
- A Developer ID Application certificate available in your login keychain.
- A notarization credential saved with `notarytool`.
- A Sparkle EdDSA signing key for update appcasts.

Create the notarization credential once:

```sh
xcrun notarytool store-credentials "CommitStandingsNotary" \
  --apple-id "you@example.com" \
  --team-id "82P3N9JUM7" \
  --password "app-specific-password"
```

Use an app-specific password from appleid.apple.com, not your normal Apple ID password.

Create the Sparkle signing key once:

```sh
.build/sparkle-tools/Sparkle-2.9.2/bin/generate_keys --account "Digg Commit Standings"
```

This key is separate from the Apple certificate. Apple signs and notarizes the app; Sparkle signs update feeds so installed apps only accept trusted updates.

## Check Readiness

Run the preflight check before trying to package:

```sh
./scripts/package-release.sh --check
```

It verifies that the Digg Developer ID certificate is installed, the notary profile exists, and Xcode can resolve the release build settings. If it reports missing items, those require Apple account/team access.

## Build The DMG

```sh
./scripts/package-release.sh
```

By default, the release package uses the Digg Apple team detected from Diem's EAS config:

- Team ID: `82P3N9JUM7`
- Bundle ID: `com.digg.commitstandings`

The script:

- Archives a Release build.
- Exports it with Developer ID signing.
- Verifies the app signature with `codesign` and `spctl`.
- Notarizes and staples the exported app.
- Creates a Sparkle update zip.
- Generates a signed `appcast.xml`.
- Creates a drag-to-Applications DMG.
- Notarizes and staples the DMG.
- Validates the final DMG with `hdiutil`, `stapler`, and `spctl`.

Output lands in `dist/`.

The important outputs are:

- `CommitStandings-...dmg`: first install, drag to Applications.
- `CommitStandings-...app.zip`: Sparkle update payload.
- `appcast.xml`: Sparkle update feed.
- `Committed.dmg`: stable download name, required on every release.

The product and the app inside the DMG are named **Committed** / `Committed.app`.
Internal target, executable, bundle ID, versioned asset names, and signing-key
account names deliberately retain their existing identifiers for update continuity.

## GitHub Releases Updates

After incrementing both version and build in `CommitStandings/Info.plist`, land
the change on `main`, then publish from `main` with the release script:

```sh
./scripts/publish-release.sh
```

The script uploads all seven assets (four Mac and three Windows), marks the release latest, and verifies the
public links. Do not hand-assemble a release: missing `Committed.dmg` breaks the
permanent download link. Appcast payload URLs must use the permanent per-tag
`releases/download/v<version>/` path.

Before publishing, run **Prepare Windows release** on `main` in the source repo:

```sh
gh workflow run windows-release.yml --repo prompthunt/committed --ref main
```

Wait for that workflow to succeed. It builds an unsigned x64 per-user NSIS
installer, signs the updater payload using `TAURI_SIGNING_PRIVATE_KEY` and
`TAURI_SIGNING_PRIVATE_KEY_PASSWORD`, and uploads `windows-release-<full-sha>`.
It never publishes a release. The Mac publishing script downloads this artifact
and refuses to continue if its version, source commit, filenames or SHA-256
digests differ from the current checkout. Node 24 and authenticated `gh` are
required on the publishing Mac. An already downloaded artifact can be supplied
with `WINDOWS_DIST_DIR=/path/to/artifact`.

Windows adds three public assets to the same release:

- `Committed-<version>-<sha8>-x64-setup.exe`: permanent updater payload.
- `Committed-Setup.exe`: identical stable download copy.
- `latest-windows.json`: version, payload URL and Tauri signature.

The manifest's installer URL is per-tag, never `latest/download/`. The update
endpoint itself uses `releases/latest/download/latest-windows.json`. Automatic
Updates downloads and verifies in the background, then installs on Quit or
**Restart to update**. Check for Updates works even with Automatic Updates off.

The dedicated updater key is separate from Sparkle and Authenticode. Back up
the private key and password outside the source tree; losing them prevents
updates to installed Windows copies. Never rotate the public key casually.
Windows builds remain unsigned, with no paid signing service or Store dependency.
Ship x64 first; Windows 11 ARM devices use x64 emulation.

Run the combined publishing script on a Mac before deploying the Windows download
announcement. A PC must never run either Mac packaging/publishing script. See
[Windows verification](windows-verification.md) for installer and update checks.

The site's Windows download starts behind
`NEXT_PUBLIC_WINDOWS_DOWNLOAD_AVAILABLE=false`, so merging source cannot expose a
missing installer link. After the script verifies the combined release's public
URLs, set that public build flag to `true` for the site and redeploy.

The public source lives in `prompthunt/committed`; official downloads and updates
remain in the separate release repository. The installed app must be able to fetch
this unauthenticated URL:

```text
https://github.com/prompthunt/commit-standings-releases/releases/latest/download/appcast.xml
```

Keep the release-hosting repo public so installed apps can fetch updates without
GitHub credentials. Preserve historical release assets and the existing signing key.

For CI, export the Sparkle private key and store it as a secret:

```sh
.build/sparkle-tools/Sparkle-2.9.2/bin/generate_keys --account "Digg Commit Standings" -x Sparkle-private-key.txt
```

Then pass it to the release script as `SPARKLE_PRIVATE_KEY`. Do not commit the private key.

## Local Packaging Test

Before the Apple credentials are ready, you can validate the script wiring without submitting to Apple:

```sh
./scripts/package-release.sh --skip-notarization --skip-git-check
```

That package is not the one to send to friends. It only proves the archive/export/DMG steps are wired.

## Friend Install Flow

Send friends the notarized `.dmg` from `dist/`.

They open the DMG, drag `Committed.app` to Applications, then launch it from Applications. Because it is Developer ID signed and notarized, Gatekeeper should allow the normal launch path without a scary unsigned-app warning.

## Compatibility

Committed requires macOS 26 or later and supports Apple silicon and Intel.
The release script defaults to `MACOSX_DEPLOYMENT_TARGET=26.0`, matching the app.

To override the Digg defaults for a one-off package:

```sh
TEAM_ID=ABCDE12345 PRODUCT_BUNDLE_IDENTIFIER=com.example.commitstandings ./scripts/package-release.sh
```

## iPhone (TestFlight, then the App Store)

The iPhone app (`CommitStandingsiOS` scheme, display name **Committed**, bundle ID
`com.addisonk.CommitStandings.iOS`, Live rank extension `com.addisonk.CommitStandings.iOS.LiveRank`)
ships through TestFlight first, then the App Store. It is **not** part of the GitHub Release:
`publish-release.sh`, its seven assets, and the Mac and Windows steps above don't change. The iOS
marketing version follows the shared version number.

### Signing and capabilities

- An App ID for the app with **Push Notifications** and the App Group
  `group.com.addisonk.CommitStandings`, and one for the extension with the same App Group.
- `CommitStandingsiOS/CommitStandingsiOS.entitlements` has `aps-environment = development`, which
  is what Debug and development-signed device builds use. Distribution signing for TestFlight and
  the App Store uses `production` (Xcode's automatic signing sets it from the distribution
  profile when exporting; with manual signing, the distribution profile must include Push
  Notifications). Without the entitlement, ActivityKit refuses push-token Live Activities and the
  app falls back to phase 1 (updated only by the app).
- The extension needs no push entitlement.

### Relay build settings

The app reads two build settings through its Info.plist:

| Setting | Debug | Release | Meaning |
|---|---|---|---|
| `COMMITTED_RELAY_URL` | empty | `https://committed-relay.prompt-hunt.workers.dev` | Base URL of the Committed relay. Empty = no relay: Live rank stays phase 1. |
| `COMMITTED_APNS_ENVIRONMENT` | `sandbox` | `production` | Sent to the relay so it pushes through the APNs host that matches `aps-environment`. |

Set `COMMITTED_RELAY_URL` to the deployed relay (for example `https://committed-relay.<subdomain>.workers.dev`)
for Release before the TestFlight upload, and to a staging Worker or `http://localhost:8787`
(`wrangler dev`) for Debug. For a one-off local build, pass it on the command line:

```sh
xcodebuild -project CommitStandings.xcodeproj -scheme CommitStandingsiOS \
  -destination 'platform=iOS Simulator,name=iPhone Duo' COMMITTED_RELAY_URL=http://localhost:8787 build
```

A TestFlight build is a Release build, so it registers with `apnsEnvironment: production`; the
relay pushes it through `api.push.apple.com`.

### APNs key and relay deploy

1. Create an **APNs auth key** (`.p8`) in the Apple Developer account. Note its key ID and the
   team ID.
2. Deploy the relay from `relay/` (Cloudflare Workers + D1); follow "Setup" in
   [relay/README.md](../relay/README.md): run the HTTP/2 spike first, create the D1 database,
   set `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` with `wrangler secret put`, then
   `wrangler deploy`. Never set `APNS_ORIGIN` on a deployed relay; it's for local development.
3. Put the deployed URL in `COMMITTED_RELAY_URL` (Release) and upload the build.

### TestFlight

The iOS targets sign with the Prompt Hunt team (`R36J43WZ34`), set as `DEVELOPMENT_TEAM` on those
targets only; the Mac app keeps signing with the team `package-release.sh` passes. Another developer
owns the App Store name "Committed", so the listing is **Committed: Commit Leaderboard**; the home
screen still shows "Committed" (`CFBundleDisplayName`). `ITSAppUsesNonExemptEncryption = NO` (HTTPS
only), so uploads skip the export-compliance question.

**Upload every build with `scripts/testflight.sh`**, from a clean checkout of `main`:

```bash
scripts/testflight.sh --notes-file notes.txt
```

The notes are the build's **What to Test** text. Write them with the
[release-notes skill](../.agents/skills/release-notes/SKILL.md), as
[TestFlight release notes](../.agents/rules/testflight-notes.md) requires; the script won't
upload without them and prints back what App Store Connect saved.

**Every TestFlight build also goes to the App Store** unless the request says TestFlight only
(`--testflight-only`). The script takes the next build number from App Store Connect, archives the
Release build, uploads it, releases it to every tester, and then submits it to App Review.

TestFlight:

- **Prompt Hunt** (internal, team members) gets every build as soon as it processes.
- **Friends** (external, for example people outside the team) gets each build after TestFlight beta
  review, which the script submits. The first build of a version takes a few hours to a day;
  later builds are usually approved quickly. Add people with
  `asc testflight testers add --app 6831797452 --email <email> --group Friends`.

App Store, through [`scripts/appstore_submit.py`](../scripts/appstore_submit.py):

- It submits the build as the version [`appstore/metadata`](../appstore/README.md) is for: it
  creates that version if needed, applies the listing with `appstore_apply.py`, uploads the
  screenshots in `docs/screenshots/app-store/`, validates, attaches the build and submits it.
  The release type is after approval, so Apple releases it as soon as it's approved.
- App Store Connect holds one unreleased version at a time. While an earlier version is waiting for
  review, in review or pending release, the build stays on TestFlight, and the script prints the
  command to submit it once that version is out:
  `python3 scripts/appstore_submit.py --build-number <n>`. A version already submitted with another
  build isn't swapped; cancel that submission first if this build should replace it.

Uploading from Xcode's Organizer instead skips the Friends group, beta review and the App Store,
so outside testers would fall behind. For a new version, bump `MARKETING_VERSION` on the iOS
targets and rename `appstore/metadata/version/<old>` to the new number with a new What's New;
`testflight.sh` refuses to upload when the two differ (unless `--testflight-only`). Build numbers
need no bump.

The App Store privacy label lists the GitHub username and the usernames of people on your board,
linked to device identifiers, for app functionality (sent to the Committed relay).

The iOS icon is a full-bleed, opaque square (iOS applies its own mask); it isn't the Mac icon,
whose rounded shape and transparent margin App Store Connect rejects.

