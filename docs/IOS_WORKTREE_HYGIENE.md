# Native work across worktrees and shared devices

Applies to the Mac app, the iPhone app and anything else that runs `xcodebuild`,
`simctl` or a Simulator from a Committed checkout.

## Start with current tooling

Fetch `origin/main` and compare this checkout's
[resource rule](../.agents/rules/resource-cleanup.md) and `scripts/ios*.py` with it
before native work. A worktree pins its own code and instructions; merging new rules
does not update existing worktrees. Bring the hygiene commits into your task branch
or use a current checkout. Another task's dirty or active checkout stays untouched:
no reset, pull or replacement. Report a blocker if updating cannot be done safely.

## One native session per machine

`python3 scripts/ios.py -- <xcodebuild arguments>` serializes builds, archives and
exports. `python3 scripts/ios_check.py mac` and `python3 scripts/ios_check.py ios`
serialize a whole check, including packaging and disposable-device cleanup. All of
them join the shared `apple-session` FIFO queue (app `Committed`), which holds the
machine-wide lock

`~/Library/Application Support/AppleDevelopment/native-session.lock`

used by Old Sport, HiFi, Diem and other apps. `~/.local/bin/apple-session status`
shows who owns the session and who is waiting.

A second agent says it is waiting, does independent code or review work, and retries
after the owner finishes. The default wait is 30 minutes; expiry starts no native
work. The owner, the lock file and the queue stay as they are: waiting is the only
path forward. The OS releases the lock when its holder exits, including a crash. The
lock is cooperative: raw Xcode sessions and unwrapped `xcodebuild` runs do not take
part, so inspect for them and coordinate before starting.

For interactive work, put the entire build/install/launch/review sequence under one
lease:

```sh
apple-session run --app "Committed" --worktree "$PWD" -- /bin/zsh -f
# or, for a scripted session:
python3 scripts/ios_session.py -- /absolute/path/to/session-script
```

The session may call `xcodebuild` and `simctl` directly. This checkout's wrappers
recognize an inherited `apple-session` lease and run inside it. For manual Xcode UI
work, keep the session shell open until the Xcode work finishes; when the lease
wrapper exits, the session is over.

## Persistent interactive roster

Reuse these existing devices by exact UDID:

| Device | UDID | Runtime | Purpose |
| --- | --- | --- | --- |
| iPhone Duo | `94D56458-B90B-484A-BA5E-16748D2CBEE5` | iOS 27.1 | iPhone app review, Duo layouts |
| iPhone 18 Pro Max | `CAE5A835-4734-4944-8CF5-4BCB043FE467` | iOS 27.0 | Conventional iPhone layout |

The iPhone app requires iOS 27.1. The iPhone 18 Pro Max stays on iOS 27.0 until a
27.1 runtime supports it, so it cannot run the iPhone app yet; review on the iPhone
Duo and report the gap. Both devices are shared with other apps; keep their saved
state. The roster is not an instruction to boot both or to delete older devices.

Read the current inventory and select an exact UDID before building:

```sh
xcodebuild -version
xcrun simctl list devices available
xcrun simctl list runtimes
```

If a roster device is missing, report a setup blocker. Adding a runtime or device
model is deliberate machine setup, not routine recovery, and per-branch simulators
are never the answer: every branch reuses the roster.

Automated tests use the single disposable test-device slot, never these persistent
devices. At most one automated-test simulator exists across Committed worktrees;
failed cleanup blocks the next creation until safely resolved. See
[native checks](IOS_CHECKS.md).

## Finish before archiving

1. Let the owned command finish; verify its disposable device is absent and its
   build/test processes ended. Shut down a persistent device only if this task booted
   it, it is idle and nobody else is using it. Keep its data. Quit Committed builds
   this task launched; leave the installed app running.
2. Report retained logs, `.xcresult` bundles, screenshots, recordings, archives and
   DMGs. Keep `build/` and `dist/` as a whole.
3. Review only this checkout's registered `build/DerivedData` for retention. It
   becomes a candidate after seven days with no file modified, and only after
   exact-path, ownership, symlink, process and open-file checks. Export needed
   evidence first. Preflight lists candidates but never deletes them.
4. Record the checkout and any retained resources or cleanup blockers in the handoff.
   For worktree retirement, verify merge status, local changes and ignored unique
   files; preserve them and use the owning tool's supported archive flow. Archiving a
   chat neither cleans simulator devices nor proves its checkout is safe to remove.
