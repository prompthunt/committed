# Public changelog and release notes

Treat the changelog, GitHub release notes, App Store What's New, and external TestFlight What to Test as public from the first draft. Write from verified, user-facing changes included in the release. Describe what someone can see or do and label the platform when availability differs.

- Exclude private conversations, private issue or repository details, unreleased plans, personal information, customer or tester identities, live board data, credentials, internal URLs and operational details. Omit anything whose suitability for public release is unclear. Use the private reporting process in [SECURITY.md](../../SECURITY.md) for vulnerability details.
- Write a fresh summary. Keep raw commits, PR descriptions, chat transcripts, logs, screenshots of live accounts, and generated summaries of private sources out of the publishing inputs. Review the exact text, links, and attachments before committing or submitting them.
- Add a [changelog](../../CHANGELOG.md) entry for the version being released. Use a level-two heading of `Desktop <version>` or `iPhone <version>`, optionally followed by a date in parentheses. Keep platform and availability accurate.
- Preview desktop notes with `scripts/publish-release.sh --print-notes`. The publishing script reads only the matching Desktop entry in the tracked changelog. It stops if the entry is missing, empty, or duplicated.
- Keep iPhone App Store What's New in the version's `appstore/metadata` and follow the [TestFlight notes rule](testflight-notes.md) for each beta build's What to Test. Both use this public-content rule.
