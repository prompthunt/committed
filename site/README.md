# gitcommitted.app — marketing site

The one-page site for **Committed**, built with Next.js (App Router) + TypeScript + Tailwind v4.
It is fully static: `npm run build` writes plain HTML/CSS/JS to `out/`.

```bash
cd site
npm ci             # Node 22 (see .nvmrc)
npm run dev        # http://localhost:3000
npm run build      # static export → site/out/
npm run typecheck
```

## What's here

| Path | What it is |
|---|---|
| `app/page.tsx` | The page: hero, contribution strip, four feature tiles |
| `components/HeroBackdrop.tsx` | The lime spotlight behind the hero popover |
| `components/ContributionStrip.tsx` | Full-bleed contribution calendar between the hero and the tiles; sweeps in on first view |
| `components/MacUI.tsx` | The app's native UI rebuilt in HTML (popover, notifications, menu bar, window switcher, People window) |
| `components/useLoop.tsx` | One shared clock so every demo tells the same story; reduced-motion users get the final frame |
| `lib/board.ts` | Demo data: people, per-frame counts, the app's real notification copy, download links |
| `lib/contributions.ts` | Seeded, decorative contribution data for the strip and the spotlight dust |
| `lib/glyph.ts` | The GitHub-cat trophy mark (from `MenuBarIcon.pdf`) as an SVG path |
| `public/avatars/` | GitHub avatars for the demo board (public use approved by the owner) |
| `app/icon.svg`, `app/opengraph-image.tsx` | Favicon and social card, generated at build |
| `app/fonts/` | Inter Tight fonts for the social card and their SIL Open Font License |
| `app/apple-icon.tsx`, `app/robots.ts`, `app/sitemap.ts` | Touch icon and crawler metadata, generated at build |
| `public/_headers` | Cloudflare MIME types for generated extensionless images |
| `vercel.json` | Vercel MIME types for generated extensionless images |

The download button points at the permanent `…/releases/latest/download/Committed.dmg` link,
so it never needs updating per release (see the release rules in `../AGENTS.md`).

## Deploying

Production runs on **Vercel**, connected to `prompthunt/committed`. The project
root is `site`, with the Next.js preset, Node `22.x`, `npm run build`, production
branch `main`, and pull-request previews. Leave the Output Directory override empty;
Vercel's Next.js builder handles the static export. `vercel.json` supplies PNG MIME
types for extensionless generated images.

The domain and DNS remain on Cloudflare. Use Vercel's current project-specific DNS
recommendation when configuring a deployment. Vercel manages HTTPS and redirects
www to the apex. Hosting credentials and account administration notes stay outside
this repository.

Cloudflare Web Analytics still uses the existing property. The root layout now loads
its verified public beacon explicitly because Pages no longer injects it.

## Download measurement

PostHog measures page views, `download_clicked` (hero/footer placement), and
`github_clicked` (header). Set `NEXT_PUBLIC_POSTHOG_KEY` to the project's public,
write-only token in Vercel's **production** environment before building. Never use
a personal API key. Contributor builds work without it; localhost and preview
hostnames never send events. See `.env.example`.

Enable **Cookieless server hash mode → Stateless** in the PostHog project's web
analytics settings. The SDK uses cookieless mode with no person profiles, session
recording, autocapture, heatmaps, or surveys. Links remain ordinary anchors and
work with JavaScript or analytics blocked; click events use `sendBeacon` without
delaying navigation.

Button clicks are download intent, not completed downloads or installations.
GitHub separately reports `download_count` for each release asset. To inspect all
published releases (including the stable and versioned DMGs):

```sh
gh api --paginate repos/prompthunt/commit-standings-releases/releases \
  --jq '.[] | select(.draft == false) | .tag_name as $tag | .assets[] | select(.name | endswith(".dmg")) | [$tag, .name, .download_count] | @tsv'
```

DMG counts include repeat downloads and verification requests. Sparkle `.app.zip`
downloads are updates and should be reported separately. For launch attribution,
use campaign links such as `?utm_source=x&utm_medium=social&utm_campaign=launch`.

## Demo snapshot

Final counts were verified against public GitHub contribution calendars on 2026-10-22,
using the app's inclusive Today / trailing 7 / trailing 30 day windows in America/Los_Angeles.
The snapshot is static, not a live feed on the website. Earlier animation frames illustrate
lead changes; they are not recorded historical events. Counts never decrease during a loop,
and each notification describes its corresponding lead change using the native copy template.

| Handle | Today |
|---|---:|
| addisonk | 223 |
| mvanhorn | 124 |
| jamielottering | 84 |
| jmzzll | 53 |
| danielkinsner | 47 |
| kropdx | 24 |

Addison's 7-day total is 2,072; 30-day total is 5,917. Sources:
`https://github.com/users/{handle}/contributions`, matching `ContributionsParser.swift`.
People rows match native You/Hidden labels rather than invented per-person source badges.
The hero retains native blue. `../scripts/render-app-icon.sh` exports the approved lime
glyph to the master PNG and native iconset; the public app keeps its old icon until the next app release.

## Verification (2026-10-22)

- Production export and TypeScript check passed on Node 22.16.0.
- In-app Browser checks at 1440px and 390px: no horizontal overflow, broken avatars, or
  console warnings/errors. Pause freezes the shared demo clock; reduced motion holds the
  final board and responds to preference changes.
- axe-core 4.14.0 WCAG A/AA checks: zero violations or incomplete checks for marketing
  content and controls at both sizes. Decorative app UI (`aria-hidden`) was excluded from
  this pass. The unfiltered audit flags low-contrast native UI text, including the blue
  selection, You badge, search placeholder, and dimmed hidden people. These mockups retain
  their app styling under the owner's delegated discretion; this is not a blanket
  accessibility certification.
- The social card renders in Inter Tight at 1200×630 without clipping; the touch icon is
  180×180. Crawler files, favicon and custom 404 are exported.
- Wrangler 4.152.0 local Pages preview: `/`, `/icon.svg`, `/opengraph-image`, `/apple-icon`,
  `/robots.txt`, and `/sitemap.xml` return 200 with the expected MIME types. Missing paths
  return the custom HTML page with HTTP 404. An older global Wrangler cannot run the
  2026-10-22 compatibility date; use a current Wrangler for local hosting checks.
- The stable download URL resolves through GitHub redirects to `Committed.dmg` with HTTP 200.
- Public apex checks pass: expected statuses/MIME for every exported route; custom 404;
  OG PNG 1200×630; touch PNG 180×180; HTTP/HTTPS www 301 preserving path/query;
  HTTP apex 301 to HTTPS. All 18 referenced scripts, styles, fonts, and avatars return 200;
  canonical/Open Graph metadata uses the apex.
- Production mobile Lighthouse 13.4.1 in Chrome incognito: 93 performance, 96 accessibility,
  100 best practices, 100 SEO; no run warnings, no browser console errors, CLS 0.
  The accessibility finding is native mockup contrast. The initial normal-profile run
  was affected by a Calendly extension error and a cache-clearing timeout, so these are
  the isolated rerun scores, not an assertion about every environment or assistive tool.
- Cloudflare Web Analytics is enabled for the verified Pages property. Automatic beacon
  injection is verified in PR #67's successful preview, as are the PR check and preview
  comment. Visitor reporting awaits traffic; no manual tracking ID is needed.

The app project stays at the repo root. This PR also aligns repository/release references
with Prompt Hunt and prepares the lime app icon; it does not publish a native app release.
