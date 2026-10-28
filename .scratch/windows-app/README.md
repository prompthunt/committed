# Committed for Windows

Bring Committed's menu-bar leaderboard to Windows as a tray app built with **Tauri 2**.

Decided in planning (2026-10-27):

- **Stack: Tauri 2.** Committed's Mac app is SwiftUI, so any Windows version is a second UI. Tauri gives a small installer, a tray icon, launch at login, notifications, and a built-in signed updater. The most popular Windows port of steipete's CodexBar (Win-CodexBar) uses Tauri 2.
- **Follow CodexBar's layout and release model.** CodexBar keeps its Linux desktop app in a subfolder of the main repo, and one version tag produces a single GitHub Release containing every platform's assets. Committed does the same: the Windows app lives in a `windows/` folder of this repo, shares the Mac app's version number, and its assets ship in the same release in `prompthunt/commit-standings-releases`.
- **Why one release matters.** The permanent `…/releases/latest/download/Committed.dmg` link and the Sparkle feed only resolve if the latest release contains the Mac assets. A Windows-only release marked latest would break Mac downloads and updates.
- **Signing:** Azure Artifact Signing, so SmartScreen doesn't warn about an unknown publisher.
- **Product behavior** follows `PRODUCT.md`; use its glossary (Competitor, Connect GitHub, Window, Contributions, Refresh).

Tickets are in `issues/`, numbered in dependency order. Tickets 05, 07, and 08 can run alongside the main chain.
