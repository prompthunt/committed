# Clean up development resources before finishing

Release the development resources a task started so finished work leaves no idle
Simulators, test runners, built app instances or dev servers holding the Mac's
memory and disk.

- Before starting resources, record the Simulator UDID and its initial state, plus the
  PID/session, command and working directory of task-owned builds, test runners,
  watchers, launched app instances and dev servers (`site/`, `windows/`). A shared
  Simulator name or a process name alone does not establish ownership.
- On completion or cancellation, stop only resources this task started, after
  verifying no user or other active task is using them. Preserve pre-existing and
  shared sessions; coordinate any explicit handoff. If ownership or current use is
  uncertain, leave the resource running and report the blocker.
- Reuse persistent development Simulators by exact UDID; shut down a task-booted
  device only after verifying it is idle, and preserve its data. Closing the
  Simulator window is not shutdown. Routine cleanup never uses `shutdown all`,
  blanket `killall`/`pkill`, device erase, deletion of historical/shared devices,
  worktree removal or RAM-purge commands.
- Automated iPhone tests run through `python3 scripts/ios_check.py ios`, never raw
  `simctl create`. Its disposable pool is the one deletion exception: at most **one
  automated-test simulator across all Committed worktrees**, deleted only when its
  durable creation receipt and exact identity match and inactivity is verified. The
  wrapper never adopts existing Simulators. Read
  [simulator-resource-hygiene](../skills/simulator-resource-hygiene/SKILL.md) before
  using any generic simulator skill.
- Stop task-owned dev servers, watchers, launched Committed builds and unfinished
  build/test processes gracefully through their original session or supported stop
  command. Recheck process identity before targeting a recorded PID, which may have
  been reused. Leave the installed Committed app, shared services and user
  applications running.

## End-of-task checklist

- [ ] Review the task's resource record; confirm which resources are still running and safe to stop.
- [ ] Let each test command finish and verify its disposable device was deleted; keep test results and attachments. For persistent devices, shut down only task-booted idle devices and keep their data.
- [ ] Verify disposable devices are absent, targeted persistent devices are `Shutdown`, and owned processes have ended; confirm by observation, not by having issued the command.
- [ ] Report cleanup results and any remaining resources, owner/handoff, reason and blocker. If access was lost, report cleanup as unverified.

Ownership receipts live outside checkouts at
`~/Library/Application Support/Committed/agent-simulators/`, so archiving a worktree
does not orphan them. File locks protect live leases; the next test command recovers
only shutdown, inactive pool-owned devices. Inspect with
`python3 scripts/ios_simulators.py status` or `cleanup` (dry run);
`cleanup --apply` removes only those verified devices. Booted abandoned devices and
uncertain ownership stay protected and produce a blocker. Interrupted jobs report
unverified cleanup; nothing runs after a forced kill.

Cleanup releases task-owned resources; it does not promise free RAM. When
investigating memory pressure, use system memory-pressure and swap evidence rather
than one process's RSS.

## One native session at a time

Every native build, test, packaging run and interactive Simulator session holds one
machine-wide lease, shared with Old Sport, HiFi, Diem and other apps on this Mac:

- `scripts/ios_session.py` joins the shared **`apple-session`** FIFO queue when it is
  installed (`~/.local/share/apple-session/apple_session.py`, CLI
  `~/.local/bin/apple-session`), registering as app `Committed`.
- Without it (CI, other machines) it takes the standalone flock at
  `~/Library/Application Support/AppleDevelopment/native-session.lock`, the same
  inode the queue holds, so both kinds of client exclude each other.
- `ios.py` holds the lease for each build/archive/export; `ios_check.py` holds it for
  the whole check, including disposable-device deletion and packaging.

`~/.local/bin/apple-session status` shows the owner and the ordered waiting
worktrees. Waiting prints a message and expires after 30 minutes without starting
work. While waiting, report it and do independent code work, then retry. The queue
is the only path to native work: wait your turn even when it is slow, keep capacity
thresholds as set, and use the single test-device slot. Failed or uncertain cleanup
keeps that slot occupied and blocks replacement until it is safely resolved. A crash
receipt left by a library session fails closed for manual inspection
(`apple-session recover --confirm-id <id>` only after its processes have stopped).
The lease is cooperative: Xcode UI sessions and unwrapped `xcodebuild` runs do not
participate, so inspect for them and coordinate before starting.

For interactive work, hold the lease for the whole build/install/run/review sequence:

```sh
apple-session run --app "Committed" --worktree "$PWD" -- /bin/zsh -f
```

Inside that shell, call `xcodebuild` and `simctl` directly, or this checkout's
wrappers (they recognize the inherited lease). Finish review and cleanup before
exiting the shell. `python3 scripts/ios_session.py -- <session-script>` is the
equivalent for a scripted session. Run session CLIs at the outermost level only:
wrapping an older checkout's non-queue-aware wrapper makes it wait on its own
parent's lease.

## Persistent devices

Reuse these existing devices by exact UDID for interactive review; branches share
them, so a new branch reuses them as they are:

| Device | UDID | Runtime | Use |
| --- | --- | --- | --- |
| iPhone Duo | `94D56458-B90B-484A-BA5E-16748D2CBEE5` | iOS 27.1 | iPhone app review, Duo layouts |
| iPhone 18 Pro Max | `CAE5A835-4734-4944-8CF5-4BCB043FE467` | iOS 27.0 | Conventional iPhone layout |

The iPhone app's deployment target is iOS 27.1, so the iPhone 18 Pro Max cannot run
it until an iOS 27.1 runtime supports that model; review on the iPhone Duo until
then and report the gap. Availability is not an instruction to boot both. Other apps
keep their own saved state on these devices; preserve it. See
[iOS worktree hygiene](../../docs/IOS_WORKTREE_HYGIENE.md) before interactive work.

## Capacity preflight and bounded commands

`python3 scripts/ios.py -- <xcodebuild arguments>` runs local builds, archives and
exports; tests use `ios_check.py`. It checks free disk before launching Xcode, keeps
output and a process receipt under `build/`, and stops its own process group after
30 minutes (`--timeout SECONDS` before `--` changes the bound; `--startup-timeout`
bounds the wait for XCTest's first suite). Builds and tests are also monitored
against a 5 GiB runtime free-space floor; hitting it stops only that command's
process group, returns exit 125 and keeps diagnostics.

`python3 scripts/ios_tools.py` checks capacity alone. The default minimum is 20 GiB;
set `COMMITTED_MIN_FREE_GIB` (or `--minimum-gib`) deliberately for an operation's
needs. A passing check is a snapshot, not a reservation.

On failure, finish active work first, review the reported cache candidates and verify
inactivity again before removing one by hand. Candidates are limited to this
checkout's `build/DerivedData`, registered when a wrapper created it, with matching
repository path and directory identity. Any running native build or test suppresses
recommendations. The preflight never deletes files. If nothing qualifies, report the
capacity blocker. Rerun preflight before retrying.

## Cache retention and archival

At handoff, record the checkout, DerivedData path, retained results and device
cleanup status. Archiving a chat is not a cleanup callback. Before retiring a
checkout, review tracked/untracked changes, merge status, ignored files, process
working directories and open files; preserve unique work and use supported worktree
archival.

Registered `build/DerivedData` becomes a manual cleanup candidate only when inactive
and its newest file is older than seven days; recheck exact paths, ownership,
symlinks, active builds and open files immediately before removing it. Keep the rest
of `build/` and `dist/`: `.xcresult` bundles, exported attachments, screenshots,
recordings, archives and DMGs have no automatic expiry. Export evidence needed from
DerivedData before retiring it.
