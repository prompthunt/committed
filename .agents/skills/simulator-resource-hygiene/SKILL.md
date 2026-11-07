---
name: simulator-resource-hygiene
description: Use when starting, finishing or recovering Committed native checks or Simulator sessions across worktrees. Enforces the shared native-session queue and bounded disposable-device ownership while preserving persistent simulators and evidence.
---

# Simulator resource hygiene

Read `.agents/rules/resource-cleanup.md` first. Its ownership rules take precedence
over any generic simulator skill's batch examples.

## Automated checks

Run `python3 scripts/ios_check.py mac` (Mac gate) or `python3 scripts/ios_check.py ios`
(iPhone app). Each waits its turn in the shared `apple-session` queue, then holds the
lease for the whole check. `ios` leases the single machine-wide test-device slot,
creates one isolated iPhone Duo / iOS 27.1 simulator, keeps test logs, results and
attachments, and deletes that exact device on completion or cancellation after
verifying ownership and inactivity. It waits up to two minutes for the slot. There is
**one automated-test simulator across Committed worktrees**: a busy slot or failed
cleanup means wait or report the blocker.

Use `--only-testing CommitStandingsiOSTests/Suite/testName` for narrow runs. Every
disposable device comes from the wrapper; raw `simctl create` and generic creation
scripts stay unused. Builds need 20 GiB free to start and stop their own process group
below 5 GiB; keep those limits.

## Interactive development

Read [worktree hygiene](../../../docs/IOS_WORKTREE_HYGIENE.md). Reuse the persistent
iPhone Duo (`94D56458-B90B-484A-BA5E-16748D2CBEE5`, iOS 27.1) by exact UDID and hold
the session lease for the entire workflow:

```sh
apple-session run --app "Committed" --worktree "$PWD" -- /bin/zsh -f
```

The iPhone 18 Pro Max (`CAE5A835-4734-4944-8CF5-4BCB043FE467`) runs iOS 27.0 and
cannot run the iPhone app until a 27.1 runtime supports it. Persistent devices are
never erased, deleted or adopted into the disposable pool; shut one down afterward
only if this task booted it and nobody else is using it. A `CommittedAgent-*` device
belongs to the lease that created it.

## Interrupted jobs and archiving

Ownership is recorded outside worktrees at
`~/Library/Application Support/Committed/agent-simulators/`. Archiving a thread is
not a cleanup callback: confirm the check has finished first. The next lease recovers
only recorded, shutdown, inactive disposable devices; active leases, booted abandoned
devices, unknown identities and uncertainty are preserved and reported. A forced kill
cannot run Python `finally` blocks.

Inspect recovery without deletion:

```sh
python3 scripts/ios_simulators.py status
python3 scripts/ios_simulators.py cleanup
```

Apply the same ownership and inactivity checks to abandoned disposable devices:

```sh
python3 scripts/ios_simulators.py cleanup --apply
```

These commands touch only pool-owned devices, never historical or persistent
simulators or runtimes. Keep `.xcresult` bundles, exported attachments, recordings
and archives. Report retained resources and blockers honestly.

## Provenance

Ported from Old Sport's simulator hygiene tooling, itself an adaptation of the
ownership, bounded-capacity and release principles in
[Callstack Simlock](https://github.com/callstackincubator/simlock/tree/ccb503534dbd2eb0933243aec9ee6739f22fc7bb).
Enforcement is the repository's dependency-free Python wrappers plus the shared
`apple-session` queue.
