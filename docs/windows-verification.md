# Windows verification for spec #21

Keep desktop checks separate from deterministic tests. This document records
what has actually been observed; unchecked items remain release gates.

## Automated

Run from `windows/`:

```powershell
npm ci
npm run version:check
npm run test:core
npm test
npm run build
cargo fmt --manifest-path core/Cargo.toml --check
cargo fmt --manifest-path src-tauri/Cargo.toml --check
cargo clippy --manifest-path core/Cargo.toml --all-targets -- -D warnings
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
npm run tauri -- build
```

The public core seam ports Mac parser, ordering, refresh, visibility, movement
and notification behavior. UI tests mock Tauri IPC. Tests do not use a live token.

## Real desktop

- [x] Debug executable starts on Windows and opens standalone Connect GitHub.
- [x] Setup follows the machine's dark theme with an opaque background.
- [x] Windows accessibility tree exposes the setup heading, privacy copy, and Connect GitHub button.
- [x] Real GitHub connection loads the board; Today, 7 days and 30 days show populated counts and re-rank immediately.
- [x] The setup stays open during browser handoff and hides when connection succeeds.
- [x] People search and hide/show work; own-row hiding is disabled. The test visibility change was restored.
- [x] Opening People hides the board; the overflow menu is keyboard reachable; Quit exits the process.
- [x] The signed-updater x64 installer builds; Authenticode reports unsigned as intended.
- [x] The per-user installer exits successfully without elevation and registers Committed in the current user's Installed apps registry.
- [ ] Tray click toggles the board next to the notification area, including alternate taskbar positions and display scaling; outside click and Escape hide it.
- [ ] Credential Manager contains `com.digg.commitstandings.windows`; relaunch restores access; Disconnect deletes it without deleting hidden choices.
- [ ] Check People source filters and complete all flows using only the keyboard.
- [ ] Menu Refresh, About, private-tip dismissal and Disconnect work on the desktop.
- [ ] Enable Launch at Login, restart Windows, verify start; disable and verify no start.
- [ ] Opt into notifications; a real crossing displays the tested copy; turning them off suppresses it.
- [ ] Check light theme, dark theme, high contrast, transparency off and reduced motion on the board.
- [ ] Narrator reads rank, name, Contributions, you, time-range changes and refresh completion/failure.
- [ ] Installed apps uninstall removes the app and login entry.
- [ ] Install an older build, publish the combined release from a Mac, then verify manual and automatic updates, signature rejection and restart behavior.
- [ ] Run `scripts/publish-release.sh` on a Mac and verify all seven assets and public links before deploying the site's Windows announcement.

GitHub approval and Narrator audio require the human. The combined release
and old-to-new update check require a Mac release; never publish from the PC.
Mac build/test is verified by the existing `macos-26` PR job.
