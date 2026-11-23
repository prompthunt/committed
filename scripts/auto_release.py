#!/usr/bin/env python3
"""Publish the Desktop release on its own once a version bump lands on `main`.

Merging a version bump is the decision to ship. A launchd agent on the publishing Mac
runs `auto_release.py run` every 30 minutes. Each run:

1. Updates a dedicated checkout to `origin/main`.
2. Compares main's version and build with the latest published appcast. Nothing to do
   unless both are higher (Sparkle ignores a release whose build number didn't rise).
3. Starts the Prepare Windows release workflow for that exact commit and returns. A later
   run continues once the build succeeds.
4. Runs `scripts/publish-release.sh` in the native `apple-session` queue.

Failures post a macOS notification and open one GitHub issue per commit and step. Each
commit gets a limited number of Windows and publish attempts, so a broken release can't
loop forever.

    python3 scripts/auto_release.py run        # one check, as the agent runs it
    python3 scripts/auto_release.py status     # what a run would do now, without acting
    python3 scripts/auto_release.py install    # set up the checkout and the launchd agent
    python3 scripts/auto_release.py uninstall  # remove the launchd agent
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
import plistlib
import re
import subprocess
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

SOURCE_REPO = "prompthunt/committed"
RELEASES_REPO = "prompthunt/commit-standings-releases"
APPCAST_URL = f"https://github.com/{RELEASES_REPO}/releases/latest/download/appcast.xml"
WINDOWS_WORKFLOW = "windows-release.yml"
LABEL = "com.prompthunt.committed.auto-release"
INTERVAL_SECONDS = 30 * 60
MAX_WINDOWS_DISPATCHES = 2
MAX_PUBLISH_ATTEMPTS = 2
PUBLISH_TIMEOUT_SECONDS = 90 * 60
MARKER = ".committed-auto-release"

HOME = Path.home()
CHECKOUT = Path(os.environ.get("COMMITTED_RELEASE_CHECKOUT", HOME / ".local/share/committed-release/checkout"))
STATE_DIR = Path(os.environ.get("COMMITTED_RELEASE_STATE", HOME / ".local/state/committed-release"))
SOURCE_CLONE = Path(os.environ.get("COMMITTED_SOURCE_CLONE", HOME / "Projects/committed"))
PLIST_PATH = HOME / "Library/LaunchAgents" / f"{LABEL}.plist"
AGENT_PATH = ":".join([
    str(HOME / ".local/share/mise/shims"),
    str(HOME / ".local/bin"),
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
])


# ---------------------------------------------------------------------------
# Decisions (pure, unit-tested)


def parse_version(text: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+(\.\d+)*", text.strip()):
        raise ValueError(f"not a dotted version: {text!r}")
    return tuple(int(p) for p in text.strip().split("."))


@dataclass(frozen=True)
class Release:
    version: str
    build: int


def parse_appcast(xml: str) -> Release:
    """The newest item in a Sparkle appcast (highest build number)."""
    builds = re.findall(r"<sparkle:version>\s*(\d+)\s*</sparkle:version>", xml)
    versions = re.findall(r"<sparkle:shortVersionString>\s*([\d.]+)\s*</sparkle:shortVersionString>", xml)
    if not builds or len(builds) != len(versions):
        raise ValueError("appcast has no readable sparkle:version / shortVersionString pairs")
    build, version = max(zip((int(b) for b in builds), versions))
    return Release(version=version, build=build)


def compare(main: Release, published: Release) -> str:
    """'publish' when main is a newer release, 'current' when it is the published one,
    'behind' when main is older, and 'build-not-bumped' when the version rose but the
    build number did not (Sparkle would never offer it)."""
    mv, pv = parse_version(main.version), parse_version(published.version)
    if mv == pv:
        return "current"
    if mv < pv:
        return "behind"
    if main.build <= published.build:
        return "build-not-bumped"
    return "publish"


def windows_state(runs: list[dict], sha: str) -> str:
    """Windows release status for one commit from `gh run list` JSON rows:
    'success', 'running', 'failed' (latest finished run did not succeed) or 'none'."""
    mine = [r for r in runs if r.get("headSha") == sha]
    if not mine:
        return "none"
    if any(r.get("conclusion") == "success" for r in mine):
        return "success"
    if any(r.get("status") != "completed" for r in mine):
        return "running"
    return "failed"


def safe_checkout(path: Path, expected: Path) -> bool:
    """Only the dedicated checkout may be reset and cleaned."""
    try:
        return path.resolve() == expected.resolve() and (path / MARKER).is_file()
    except OSError:
        return False


# ---------------------------------------------------------------------------
# Side effects


def log(msg: str) -> None:
    stamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{stamp}] {msg}", flush=True)


def sh(*args: str, cwd: Path | None = None, check: bool = True, timeout: int = 300) -> str:
    out = subprocess.run(args, cwd=cwd, check=check, capture_output=True, text=True, timeout=timeout)
    return out.stdout.strip()


def load_state() -> dict:
    try:
        return json.loads((STATE_DIR / "state.json").read_text())
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE_DIR / "state.json.tmp"
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True))
    tmp.replace(STATE_DIR / "state.json")


def notify(title: str, message: str) -> None:
    script = f"display notification {json.dumps(message)} with title {json.dumps(title)}"
    subprocess.run(["osascript", "-e", script], capture_output=True)


def alert(state: dict, sha: str, kind: str, title: str, body: str) -> None:
    """Notify on this Mac and open one issue per commit and failure kind. The source repo
    is public: keep bodies to versions, commits and steps, never logs or local paths."""
    notify("Committed release", title)
    key = f"{sha}:{kind}"
    alerted = state.setdefault("alerted", [])
    if key in alerted:
        return
    try:
        sh("gh", "issue", "create", "--repo", SOURCE_REPO, "--title", title,
           "--label", "bug", "--body", body + "\n\nOpened by `scripts/auto_release.py` on the publishing Mac. "
           "Its log is in `~/.local/state/committed-release/logs/`.")
    except subprocess.SubprocessError as exc:
        log(f"could not open issue: {exc}")
    alerted.append(key)


def fetch_appcast() -> str:
    req = urllib.request.Request(APPCAST_URL, headers={"User-Agent": "committed-auto-release"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode()


def sync_checkout() -> str:
    if not safe_checkout(CHECKOUT, CHECKOUT):
        raise SystemExit(f"{CHECKOUT} is not the dedicated release checkout; run `auto_release.py install`.")
    sh("git", "fetch", "--quiet", "origin", "main", cwd=CHECKOUT, timeout=600)
    sh("git", "checkout", "--quiet", "--detach", "--force", "origin/main", cwd=CHECKOUT)
    sh("git", "reset", "--quiet", "--hard", "origin/main", cwd=CHECKOUT)
    sh("git", "clean", "-ffdxq", "-e", MARKER, cwd=CHECKOUT)
    return sh("git", "rev-parse", "HEAD", cwd=CHECKOUT)


def main_release() -> Release:
    plist = plistlib.loads((CHECKOUT / "CommitStandings/Info.plist").read_bytes())
    return Release(version=plist["CFBundleShortVersionString"], build=int(plist["CFBundleVersion"]))


def windows_runs(sha: str) -> list[dict]:
    raw = sh("gh", "run", "list", "--repo", SOURCE_REPO, "--workflow", WINDOWS_WORKFLOW,
             "--commit", sha, "--limit", "20", "--json", "databaseId,headSha,status,conclusion")
    return json.loads(raw or "[]")


def plan(dry_run: bool) -> int:
    state = load_state()
    sha = sync_checkout()
    main = main_release()
    published = parse_appcast(fetch_appcast())
    verdict = compare(main, published)
    log(f"main {main.version} ({main.build}) at {sha[:8]}; published {published.version} ({published.build}): {verdict}")

    if verdict in ("current", "behind"):
        return 0
    if verdict == "build-not-bumped":
        if not dry_run:
            alert(state, sha, "build", f"Desktop {main.version} can't ship: build number not bumped",
                  f"`main` ({sha[:8]}) is version {main.version} with build {main.build}, but the latest "
                  f"release is build {published.build}. Raise `CFBundleVersion` in `CommitStandings/Info.plist`.")
            save_state(state)
        return 1

    notes = subprocess.run(["scripts/publish-release.sh", "--print-notes"], cwd=CHECKOUT,
                           capture_output=True, text=True)
    if notes.returncode != 0:
        log("no changelog entry for this version")
        if not dry_run:
            alert(state, sha, "notes", f"Desktop {main.version} can't ship: no changelog entry",
                  f"`main` ({sha[:8]}) is version {main.version}, but `CHANGELOG.md` has no "
                  f"`## Desktop {main.version}` entry.")
            save_state(state)
        return 1

    attempts = state.setdefault("attempts", {}).setdefault(sha, {"windows": 0, "publish": 0})
    win = windows_state(windows_runs(sha), sha)
    log(f"Windows build for {sha[:8]}: {win}")
    if win == "running":
        return 0
    if win in ("none", "failed"):
        if attempts["windows"] >= MAX_WINDOWS_DISPATCHES:
            if not dry_run:
                alert(state, sha, "windows", f"Desktop {main.version}: Windows release build failed",
                      f"Prepare Windows release failed {attempts['windows']} times for {sha[:8]}. "
                      "Fix it, then rerun the workflow on `main`; the next check publishes.")
                save_state(state)
            return 1
        if dry_run:
            log("would start the Windows release build")
            return 0
        head = sh("git", "ls-remote", "origin", "refs/heads/main", cwd=CHECKOUT).split()[0]
        if head != sha:
            log("main moved since fetch; next run picks up the new commit")
            return 0
        sh("gh", "workflow", "run", WINDOWS_WORKFLOW, "--repo", SOURCE_REPO, "--ref", "main")
        attempts["windows"] += 1
        save_state(state)
        log("started the Windows release build; a later run publishes once it succeeds")
        return 0

    if attempts["publish"] >= MAX_PUBLISH_ATTEMPTS:
        log("publish attempts used up for this commit; waiting for a fix")
        return 1
    if dry_run:
        log(f"would publish v{main.version}")
        return 0

    attempts["publish"] += 1
    save_state(state)
    logs = STATE_DIR / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    log_file = logs / f"publish-{main.version}-{dt.datetime.now():%Y%m%d-%H%M%S}.log"
    log(f"publishing v{main.version}; log: {log_file}")
    with log_file.open("w") as out:
        try:
            code = subprocess.run(
                ["apple-session", "run", "--app", "Committed", "--worktree", str(CHECKOUT),
                 "--", "scripts/publish-release.sh"],
                cwd=CHECKOUT, stdout=out, stderr=subprocess.STDOUT, timeout=PUBLISH_TIMEOUT_SECONDS,
            ).returncode
        except subprocess.TimeoutExpired:
            code = 124
    if code == 0:
        log(f"published v{main.version}")
        notify("Committed release", f"Published Desktop {main.version}")
        return 0
    log(f"publish exited {code}")
    alert(state, sha, "publish", f"Desktop {main.version}: publishing failed",
          f"`scripts/publish-release.sh` exited {code} for {sha[:8]} (attempt {attempts['publish']} of "
          f"{MAX_PUBLISH_ATTEMPTS}). If the release was created but its link checks failed, fix the "
          "release by hand; the job won't publish the same version again.")
    save_state(state)
    return 1


def run(dry_run: bool) -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with (STATE_DIR / "lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log("another release check is running")
            return 0
        return plan(dry_run)


def install() -> int:
    if not CHECKOUT.exists():
        CHECKOUT.parent.mkdir(parents=True, exist_ok=True)
        sh("git", "-C", str(SOURCE_CLONE), "fetch", "--quiet", "origin", "main", timeout=600)
        sh("git", "-C", str(SOURCE_CLONE), "worktree", "add", "--detach", str(CHECKOUT), "origin/main")
        (CHECKOUT / MARKER).write_text("Dedicated checkout for scripts/auto_release.py. It is reset to origin/main.\n")
        # mise refuses an untrusted config, which would hide node from the publish script.
        subprocess.run(["mise", "trust", str(CHECKOUT)], capture_output=True)
    elif not safe_checkout(CHECKOUT, CHECKOUT):
        raise SystemExit(f"{CHECKOUT} exists but is not the dedicated release checkout.")
    (STATE_DIR / "logs").mkdir(parents=True, exist_ok=True)
    agent = {
        "Label": LABEL,
        "ProgramArguments": ["/usr/bin/python3", "-I", str(CHECKOUT / "scripts/auto_release.py"), "run"],
        "StartInterval": INTERVAL_SECONDS,
        "RunAtLoad": True,
        "WorkingDirectory": str(CHECKOUT),
        "EnvironmentVariables": {"PATH": AGENT_PATH, "HOME": str(HOME)},
        "StandardOutPath": str(STATE_DIR / "logs/agent.log"),
        "StandardErrorPath": str(STATE_DIR / "logs/agent.log"),
        # Standard, not Background: Background throttles CPU and disk so hard that even
        # Python startup stalls, and publishing runs a full Xcode archive and notarization.
        "ProcessType": "Standard",
    }
    PLIST_PATH.parent.mkdir(parents=True, exist_ok=True)
    PLIST_PATH.write_bytes(plistlib.dumps(agent))
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", f"{domain}/{LABEL}"], capture_output=True)
    sh("launchctl", "bootstrap", domain, str(PLIST_PATH))
    log(f"installed {LABEL}: checks every {INTERVAL_SECONDS // 60} minutes from {CHECKOUT}")
    return 0


def uninstall() -> int:
    subprocess.run(["launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"], capture_output=True)
    PLIST_PATH.unlink(missing_ok=True)
    log(f"removed {LABEL}; the checkout at {CHECKOUT} is left in place")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["run", "status", "install", "uninstall"])
    args = parser.parse_args(argv)
    if args.command == "install":
        return install()
    if args.command == "uninstall":
        return uninstall()
    return run(dry_run=args.command == "status")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
