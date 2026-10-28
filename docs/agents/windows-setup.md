# Building Committed for Windows on a PC

These steps are for an agent working on a Windows PC to build Committed for Windows (spec #21). Assume the PC has only this repository and an authenticated `gh`. Run the commands in PowerShell, in order.

## 1. Check the starting point

```powershell
gh auth status
winget --version
```

Windows 11 includes `winget`. If either command fails, stop and ask the user to fix it.

## 2. Install the toolchain

```powershell
winget install -e --id OpenJS.NodeJS.LTS
winget install -e --id Rustlang.Rustup
winget install -e --id Microsoft.VisualStudio.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

The Build Tools installer needs administrator rights. Tell the user to approve the Windows permission prompt, because you can't. The install takes 5–15 minutes.

Windows 11 includes WebView2. Check for it and install it only if this prints nothing:

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue | Select-Object pv
# only if empty:
winget install -e --id Microsoft.EdgeWebView2Runtime
```

Reload `PATH` so this session sees the new tools, then verify them:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
rustup default stable
node -v; npm -v; rustc -V; cargo -V
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
```

The last command must print a path. If it prints nothing, the C++ tools are missing and Rust can't link.

## 3. Configure git for this repository

```powershell
git config http.version HTTP/1.1
git config http.postBuffer 524288000
git config core.longpaths true
```

Pushing to GitHub fails with HTTP 400 without the first two settings. The third one handles deep `node_modules` and `target` paths.

## 4. Install the agent skills

```powershell
npx -y skills add mattpocock/skills -g -y --copy -a claude-code -s implement-spec tdd code-review diagnosing-bugs codebase-design domain-modeling
npx -y skills add nodnarbnitram/claude-code-extensions -g -y --copy -a claude-code -s tauri-v2
```

If you are not Claude Code, replace `claude-code` with your agent, for example `codex`. Keep `--copy`, because symlinks on Windows need Developer Mode. Restart the agent session afterward so it loads the skills.

## 5. Read the plan

```powershell
gh issue view 21 --repo prompthunt/committed
gh issue list --repo prompthunt/committed --state open
```

The spec is #21. Its tickets are #22–#29, #31 and #32, linked as sub-issues with blocked-by relationships.

The following decisions are settled. Don't reopen them:

- The app is built with Tauri 2, in the `windows/` folder.
- Windows builds ship **unsigned**. Don't add code signing, whether paid (Azure Artifact Signing), free (SignPath) or through the Microsoft Store.
- Each version is one GitHub Release in `prompthunt/commit-standings-releases`, with the Mac and Windows assets together. This follows CodexBar.

## 6. Build it

The user starts the work by typing `/implement-spec #21`. That skill can't start itself.

Follow these rules on the PC:

- **Never publish.** Don't run `scripts/package-release.sh` or `scripts/publish-release.sh`, and don't create releases in `prompthunt/commit-standings-releases`. Mac releases are notarized on the Mac, and a real release with both platforms is published from there.
- **Leave the Mac app alone.** You can't build it here. Don't touch `CommitStandings/` unless a ticket requires it. The `macos-26` CI job builds and tests the Mac app on every PR. If #29 changes `scripts/publish-release.sh`, keep all four Mac assets and their link checks (see `AGENTS.md` → Releasing), and say in the PR that the script needs a run on a Mac.
- **The updater key (#29):** generate it with `npx tauri signer generate`. Store the private key and its password as repository secrets with `gh secret set`, and never commit either one. Tell the user where the local copy is so they can back it up: if the key is lost, installed copies can no longer update.
- **Manual checks:** several tickets need checks on the real desktop: the tray, notifications, Credential Manager, Narrator, the installer and launch at login. Run the app and do what you can. In the PR, list each check as done or as needing the user, and ask the user to confirm anything you can't observe.
