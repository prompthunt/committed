# 04: Refresh and saved data

**What to build:** The board keeps itself current and survives relaunch, matching the Mac app's Refresh behavior. It refreshes Contributions in the background about every 5 minutes and syncs the people list about every 15 minutes. Opening the tray window refreshes only if data is older than about 2 minutes. Switching Windows shows cached numbers instantly and fetches only when that Window is stale or missing. During a refresh, cached values stay visible and pulse gently; the first load shows placeholders and a "Fetching the first set of standings" message. **Refresh** reloads both the people list and Contributions. The people list and counts are saved locally, so a relaunch shows saved numbers while new data loads.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Background refresh runs about every 5 minutes; people sync about every 15 minutes
- [ ] Reopening the window within about 2 minutes doesn't trigger a refresh
- [ ] Switching Windows shows cached numbers immediately
- [ ] Cached rows pulse during refresh; the first load shows placeholders and the first-load message
- [ ] After relaunch, saved people and counts appear before new data arrives
- [ ] Rows distinguish loading, cached, and failed states
