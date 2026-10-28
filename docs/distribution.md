# Distributing Committed

Committed is a menu bar app. The friend-install build should be distributed as a signed, notarized DMG with the app and an Applications shortcut inside.

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
