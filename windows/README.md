# Committed for Windows

A Tauri 2 notification-area app. The Rust board core owns GitHub access,
ranking, refreshes, visibility, movement and notifications. The TypeScript UI
uses commands and events; credentials never cross IPC.

## Develop

Install Node 24, stable Rust with the MSVC target, Visual Studio C++ Build Tools,
and WebView2. See [the PC setup guide](../docs/agents/windows-setup.md).

```powershell
cd windows
npm ci
npm run tauri -- dev
```

First launch opens Connect GitHub. The setup window stays open during the browser
handoff. Click the tray icon to show or hide the board; Escape or clicking outside
hides it. Standalone windows close to the tray. Quit fully exits.

```powershell
npm run test:core
npm test
npm run build
cargo check --manifest-path src-tauri/Cargo.toml --locked
npm run tauri -- build
```

The per-user, unsigned NSIS installer lands in
`src-tauri/target/release/bundle/nsis/`. It requires no administrator rights.
Windows may show SmartScreen: choose **More info → Run anyway**.
Uninstall through **Settings → Apps → Installed apps**.

The launcher synchronizes the version from the Mac Info.plist before invoking
Tauri. Commit the generated version changes and Cargo lockfile with each version
bump. `npm run version:check` detects drift. x64 ships first; Windows 11 on ARM
uses x64 emulation until a native ARM64 build is added.

Board data and settings live in Tauri's per-user app-data directory. The token
lives in Windows Credential Manager under `com.digg.commitstandings.windows`.
Disconnect deletes the credential and cached board; hidden choices remain per
GitHub account. Tokens are sent only to `api.github.com`; contribution pages
are always fetched anonymously. Profile images load from GitHub's avatar host.

The core tests use injected HTTP, clock, storage, credentials and notifier fakes.
They assert through public commands and returned boards. The thin UI smoke tests
use Tauri IPC mocks. There is no live GitHub access in tests.

The board always uses an opaque background, follows the system theme, respects
forced colors and reduced motion, and supports keyboard time-range navigation.
See [manual verification](../docs/windows-verification.md) for desktop checks.

## Distribution

Windows CI builds installers without Authenticode signing. Updater signatures
use a separate Tauri key. Only the Mac's release script publishes the combined
release; never publish from this PC. See [distribution](../docs/distribution.md).
