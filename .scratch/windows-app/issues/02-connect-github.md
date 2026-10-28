# 02: Connect GitHub

**What to build:** A standalone setup window that runs GitHub's device flow with the same OAuth client ID and `read:org read:user` scopes the Mac app uses. The window shows the code, opens GitHub in the browser, and stays open during the hand-off. The token is stored in Windows Credential Manager and sent only to GitHub. Once connected, the tray window shows your own row with the "you" badge and your Contributions for the selected Window. **Disconnect GitHub** deletes the token and returns to the setup window. Copy says "Connect GitHub" and "Disconnect GitHub", never "sign in" or "log out".

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] First launch shows the setup window; approving the code on GitHub connects the app without restarting it
- [ ] The token is stored in Windows Credential Manager, survives relaunch, and is never written to disk in plain text
- [ ] Denied, expired, and slow-down device-flow responses show clear messages and allow retry
- [ ] Your own row shows your avatar, name or handle, "you" badge, and Contributions
- [ ] Disconnect GitHub deletes the stored token and returns to the setup window
