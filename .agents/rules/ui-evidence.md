# UI evidence

Applies to any visible change in the Mac app, the iPhone app, the Windows app or
the marketing site: layout, styling, navigation, controls, loading, empty, error
and other interaction states.

## Capture and inspect

- Run the changed app and exercise the affected flow. Capture real screenshots from
  the final implementation: the Mac app or `scripts/build-flow-capture.py`'s fixture
  host for Mac surfaces, a persistent iPhone Simulator for the iPhone app (see
  [resource cleanup](resource-cleanup.md) for the device roster and session lease),
  and the in-app browser for `site/`.
- Include before/after states when a baseline is available, plus each important
  changed interaction state. Every screenshot is a runtime capture; a missing
  baseline is reported as missing.
- Two exceptions may use labelled renders instead: surfaces the headless Simulator
  can't draw (Live Activities, the Dynamic Island, widgets on the Home Screen or Lock
  Screen) and App Store marketing frames. Render the real views with `ImageRenderer`
  or a `UIWindow` in a committed test, fed real app state (what `AppModel` publishes),
  not hand-built values. Say "render, not runtime capture" in the manifest's `notes`
  and in the PR comment's labels.
- Wait for transitions, avatars and images to settle unless the loading state is the
  subject. Inspect each capture for clipping, missing content, wrong states and
  unreadable text, in light and dark appearance when the change affects color.
- Use fixtures (the flow-capture host, the iPhone app's screenshot fixture) or an
  account you are authorized to show. GitHub screenshots must never expose tokens,
  private repository names or other people's private contribution data.

## Post to GitHub

- Before handing off any UI change, post a **comment on its pull request** with inline
  screenshot images. A PR description, chat attachment, local path or link-only index
  does not count.
- Upload screenshots as **direct GitHub attachments** and embed the attachment URLs
  GitHub generates. With gh 2.102 or later:

  ```sh
  gh pr comment <number> --body-file evidence.md \
    --attach './board.png#Board — ranked list, signed in' --attach './empty.png#Board — no friends yet'
  ```

  A body reference such as `![Board](./board.png)` is rewritten to the uploaded asset;
  unreferenced attachments are appended. Run `gh pr comment --help` to confirm the
  installed version supports `--attach`; otherwise use the comment box's attachment
  control in the in-app browser.
- Embed only attachment URLs. Repository file URLs (`blob/...`, `raw/...`,
  `?raw=true`, `raw.githubusercontent.com`) can render on signed-in desktop yet fail
  inline in GitHub mobile. Committed screenshots stay useful as provenance; they do
  not replace attachments.
- Keep attachments inside the repository's own GitHub access controls. If direct
  upload is unavailable, report the blocker instead of hosting images elsewhere or
  copying temporary signed URLs.
- Label each screenshot with the screen/state and what changed. State the device
  (e.g. iPhone Duo Simulator, MacBook Pro 14"), OS, fixture or live data, the capture
  commit and the relevant checks. Distinguish a simulator or fixture-host capture
  from a shipped release build.
- After posting, read the saved comment back (`gh pr view <number> --comments` or the
  API), confirm it uses the generated attachment URLs, and visually verify that the
  images render inline in GitHub without clicking them. Report the surface you
  checked (desktop or mobile) and include the comment URL in the handoff.
- Keep **one evidence comment** per PR. After a material UI revision, edit that
  comment with new captures rather than adding another. When it is your latest
  comment, use `gh pr comment <number> --edit-last --body-file evidence.md --attach …`.
  Otherwise use the comment's edit control in the in-app browser to attach the new
  images; `gh api -X PATCH repos/prompthunt/committed/issues/comments/<id> -F body=@evidence.md`
  fits only a body that already carries generated attachment URLs.
- If capture or upload is blocked, state the exact blocker in the PR comment and the
  handoff. Claim attachment or visual verification only after it happened.
- This rule authorizes posting UI evidence to the task's own PR; it does not
  authorize merging, releasing or publishing anything else.

## Storage and provenance

Commit screenshot evidence worth keeping, with short capture notes, under
`docs/screenshots/<change>/`. Build output and temporary captures stay out of git.

For each new committed runtime screenshot or labelled render, add an entry to
`docs/screenshots/<change>/manifest.json`:

```json
{
  "device": "iPhone Duo Simulator",
  "os": "iOS 27.1",
  "screenshots": [
    {
      "file": "board.png",
      "caption": "Board — ranked list, signed in",
      "capture": { "sourceCommit": "<40-character commit>", "fixture": true }
    }
  ]
}
```

`sourceCommit` is the full 40-character revision; `fixture` is an explicit boolean
(fixture `true`, live data `false`). Per-capture `device` and `os` override the
manifest defaults.

Run `python3 scripts/screenshot_evidence.py --base origin/main` after committing. It
checks images added relative to the merge-base, so historical evidence never blocks
unrelated work. App icons and asset catalogs, `docs/design/` references, `fixtures/`,
`site/public/`, `video/`, Windows icons and Windows UI assets (`windows/src/assets/`) are exempt; every other new image needs
capture provenance. Add any new exemption explicitly in the checker. A passing check
covers local storage only; direct attachments and inline verification above remain
required.
