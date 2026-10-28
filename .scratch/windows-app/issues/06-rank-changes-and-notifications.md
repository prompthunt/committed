# 06: Rank changes and notifications

**What to build:** Small chevrons show each row's rank change since the first refresh of the day; hiding or showing people starts a new baseline. Your rank appears on the tray icon (or its tooltip, if the icon can't render it legibly) when you have visible rivals. Leaderboard Notifications are opt-in from the ⋯ menu and send a Windows notification when someone passes you or you pass them, using the same copy rules as the Mac app. Hidden people never trigger notifications.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Chevrons reflect rank changes since the day's first refresh and reset on a new day
- [ ] Hiding or showing someone resets the movement baseline
- [ ] Your rank is visible from the tray when you have visible rivals
- [ ] With notifications on, a crossing produces one Windows notification; with them off, none
- [ ] Notification copy matches the Mac app's tested copy
