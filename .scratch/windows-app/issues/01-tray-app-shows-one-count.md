# 01: Tray app that shows one person's contributions

**What to build:** A Tauri 2 app in a `windows/` folder of this repo that runs on Windows with a tray icon. Clicking the icon opens a small borderless window anchored next to the tray, with a Today / 7 days / 30 days switch and the Contributions count for one GitHub username. Counts come from the public `github.com/users/<name>/contributions` page, fetched from the native side (not the webview) and parsed with the same rules as the Mac app's contributions parser, including both the modern tooltip form and the legacy forms. The app's version comes from the Mac app's version so both platforms always share one number. CI builds an unsigned Windows installer on every PR that touches the Windows app.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Running the app on Windows shows a tray icon; clicking it toggles a window positioned next to the tray, and clicking elsewhere hides it
- [ ] The window shows the Contributions count for a username for Today, 7 days, and 30 days, summing daily counts locally
- [ ] The parser's behavior matches the Mac parser's test cases, ported as tests (modern tooltip HTML, legacy `data-count`, legacy `aria-label`, "No contributions" → 0, no cells → error)
- [ ] The app's version matches the Mac app's `CFBundleShortVersionString`
- [ ] A GitHub Actions job on a Windows runner builds the installer and uploads it as a workflow artifact
- [ ] The Mac build and tests are unaffected
