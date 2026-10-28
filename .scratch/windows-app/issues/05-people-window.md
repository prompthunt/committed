# 05: People window

**What to build:** A **People…** window with an alphabetical list of Competitors, search, and All / Following / Organizations filters. Clicking the eye hides someone; clicking the eye-slash shows them again. Hidden people stay in the list so they can be restored. You can't hide yourself, and there is no manual add or remove. Visibility choices are saved locally per GitHub account and survive relaunch, disconnecting and reconnecting, refreshes, and someone leaving and rejoining a source. Hidden people are excluded from rankings and contribution refreshes. The window shows people-sync status.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Search and the three filters narrow the list as expected
- [ ] Hiding someone removes them from the leaderboard immediately; showing them restores them
- [ ] Your own row cannot be hidden
- [ ] Visibility persists per GitHub account across relaunch and Disconnect/Connect GitHub
- [ ] Hidden people are not fetched during contribution refreshes
