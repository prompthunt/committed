# 03: Leaderboard of your people

**What to build:** After you connect, the app loads every Competitor: you, the people you follow, and accessible members of your GitHub organizations, paging through every result. Each username appears once even when it comes from multiple sources. Only a complete, successful fetch replaces the saved people list; a failed fetch keeps the previous list and shows a retry message. The tray window shows your summary above a ranked leaderboard with rank, avatar, username, and Contributions for the selected Window, sorted highest first using the same ordering rules as the Mac app's ranking. A person with no data shows a placeholder, not zero.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] Followed users and organization members load across all pages and are de-duplicated by username
- [ ] A partially failed fetch leaves the previous people list in place and shows a retry message
- [ ] Rows are ordered the same way as the Mac app for the same data, including ties
- [ ] Switching the Window re-ranks the board
- [ ] Your summary shows your avatar, name, and Contributions above the list
- [ ] It does not crawl other people's following lists
