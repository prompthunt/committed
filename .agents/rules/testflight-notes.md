# TestFlight release notes

Applies every time an agent writes, rewrites or submits an iPhone build's **What to Test**
notes, including `scripts/testflight.sh` runs.

## Required writing skill

Read and apply the repository's [release-notes skill](../skills/release-notes/SKILL.md) before
drafting each build's notes. It is the only required writing skill for this copy: follow its
categorized, user-facing format rather than adding another copywriting or compression pass. The
local copy records its upstream revision and MIT license (`UPSTREAM.md`, `LICENSE`).

The reader is a friend trying Committed on TestFlight. Explain what changed for them and why it
matters.

## Format and accuracy

- Group entries under the categories that apply: **New Features**, **Improvements**, **Bug
  Fixes**, **Breaking Changes**, **Deprecations**. Omit empty ones.
- Lead each entry with the benefit, name the feature or problem, and keep it to one to three
  sentences in plain language, in a friendly consumer-app tone. Add a test step when it helps
  the reader find or try the change ("Add Committed Board from the widget gallery").
- Cover every change in the build; there's no word or bullet cap beyond App Store Connect's
  4,000 characters.
- Write from verified changes actually in the build (the commits since the last uploaded
  build). Never invent benefits, numbers or certainty. Include known issues and anything the
  reader must do.
- Keep internal jargon, PR and issue numbers, implementation details, test counts, CI, signing
  and hashes out; they belong in the PR.

## Release workflow

Write the notes as plain text with the category headings and bullets kept, and no Markdown
markers (`New Features`, then `- Committed Board: …`). Pass the file to
`scripts/testflight.sh --notes-file <file>`. The script refuses to upload without notes, submits
them as the build's What to Test text, and prints them back from App Store Connect so you can
confirm what testers see. This rule adds no separate approval step.
