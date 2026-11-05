# Native checks

Local native checks run through `scripts/ios_check.py`, which holds the shared
native-session lease (see [worktree hygiene](IOS_WORKTREE_HYGIENE.md)) for the whole
check. A second agent waits in the queue instead of starting another native session.

## Mac gate

```sh
python3 scripts/ios_check.py mac             # build + test CommitStandings
python3 scripts/ios_check.py mac --package   # then scripts/package-release.sh --skip-notarization --skip-git-check
```

`mac` runs the same `xcodebuild -scheme CommitStandings -configuration Debug
-destination platform=macOS` build and test as CI, with ad hoc signing and no team,
so no signing credentials are used. It writes DerivedData to this checkout's
`build/DerivedData` (registered for the capacity preflight) and keeps the log and
`tests.xcresult` under `build/check-mac-<timestamp>/`. `--package` runs the local
packaging smoke test inside the same lease after the tests pass; it uses the
maintainer's signing setup like any `package-release.sh` run.

Release packaging (`scripts/publish-release.sh`) also drives `xcodebuild`; run it as
the only native session. `apple-session run` keeps the terminal attached (signing and
notarization output stay visible) and has no deadline:

```sh
apple-session run --app "Committed" --worktree "$PWD" -- scripts/publish-release.sh
```

## iPhone app

```sh
python3 scripts/ios_check.py ios
python3 scripts/ios_check.py ios --only-testing CommitStandingsiOSTests/BoardArrangementTests
```

`ios` needs the shared `CommitStandingsiOS` scheme, which lands with the iPhone app
(spec #39). In a checkout without it the command exits 2 with "iPhone app not in this
checkout" before joining the queue or creating a simulator.

With the scheme present it requires the iOS 27.1 Simulator runtime, prints the Xcode
and runtime versions, leases the single disposable test-device slot, creates one
`CommittedAgent-<token>` iPhone Duo / iOS 27.1 simulator, compiles the app and its
tests once (`build-for-testing`), and runs `CommitStandingsiOSTests` (or the
`--only-testing` selection). It keeps logs, `device.json`, `tests.xcresult`,
`summary.json` and exported attachments under `build/check-ios-<timestamp>/`, then
deletes only its verified, inactive device on completion or cancellation. Persistent
devices and their data are untouched.

## Bounds and CI

Each build or test command is capped at 30 minutes (`--test-timeout`), test-runner
startup at three minutes after compilation, and individual iPhone tests at three
minutes. Builds need 20 GiB free to start (`COMMITTED_MIN_FREE_GIB`) and stop their
own process group below 5 GiB. See the
[resource rule](../.agents/rules/resource-cleanup.md) for capacity, recovery and
ownership limits.

CI is unchanged: `.github/workflows/ci.yml` runs the Mac build and test directly on
GitHub's `macos-26` runner, where no other session competes for the machine.

## Script tests

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
```
