# 08: Ship Windows in the same release, with auto-update

**What to build:** Following CodexBar, each Committed version is one GitHub Release in `prompthunt/commit-standings-releases` that contains the Mac and Windows assets. The Windows installer for the release commit is built in CI, and the release process attaches it, the Tauri update manifest, and a stable-named Windows installer to the same release as the Mac assets. The Mac assets and their checks must stay exactly as they are. Installed Windows copies update through Tauri's updater, which reads a signed manifest from the latest release. The ⋯ menu gains **Automatic Updates** and **Check for Updates…**, and a pending update is signaled in the app.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] One release contains the four existing Mac assets plus the Windows installer, a stable-named Windows installer, and the update manifest
- [ ] A permanent `…/releases/latest/download/<stable Windows installer>` link resolves, and the release process verifies it along with the existing Mac links
- [ ] The release process refuses to publish if the Windows assets for this exact version are missing
- [ ] The Tauri update manifest is signed with a dedicated updater key whose private half is never committed
- [ ] An installed older build finds, downloads, and installs the new version; Automatic Updates and Check for Updates… both work
- [ ] The repo's release docs and its required-asset table are updated
- [ ] No Mac release behavior changes: `Committed.dmg`, `appcast.xml`, and per-tag enclosure URLs still resolve
