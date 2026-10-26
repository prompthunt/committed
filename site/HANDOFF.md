# Marketing site design and maintenance

The static site lives in `site/`, alongside the native Xcode project. Build and
verification commands are in [README.md](README.md).

## Design decisions

- One hero and an eight-card feature grid. Keep the page short;
  do not add sections, pricing, testimonials, or extra copy without agreement.
- The approved wide-anchor grid has two large cards (GitHub connection and rank
  notifications), two medium cards (friends/teammates and time frames), and four
  compact cards (privacy, menu-bar rank, open source, and native macOS).
- The cards use the editorial treatment chosen on 2026-10-24 (PR #9). Each card is
  indexed and left-aligned: a monospace folio line (`01 Setup`), one visual, and a
  bottom-anchored headline. The cards come in three inks: lime (connect, macOS), paper
  `#EFEEE7` (privacy, time frame), and ink `#0C0D0A` (the rest). Each visual is a crop of
  a real app screen (`components/MacUI.tsx`), using the app's copy: the setup screen
  (`SignInView`), the People window (`FullRankingsView`), the private-contributions tip,
  the menu-bar item, the popover's segmented control and summary card, the
  notifications, and the `⋯` menu's checkboxes. Open source shows the repo name.
- Each card is a CSS size container, and its type uses `cqi` clamps. This keeps the
  type proportional from 320px phones through iPhone Duo's outer (466pt) and inner
  (951pt) displays to the 1,240px desktop container. The desktop grid starts at 1100px.
- The notification card has a Mac menu bar flush with its top edge, a demo clock,
  translucent glass banners underneath on the right, and a bottom-left caption.
- The time-frame card uses the popover's real segmented control (native blue) and summary
  card; the control works and switches between the Today, 7-day, and 30-day totals.
- The hero is centered copy (title, one-line description, download) over a Mac desktop
  (`components/HeroDesktop.tsx`, `.desk-*` in `globals.css`), framed as a display as wide
  as the feature grid (1,240px max) with a bezel from 640px up and edge to edge on phones:
  a lime wallpaper, a real macOS menu bar, and the Committed popover hanging from its
  menu-bar item, measured so it stays centered under the item and on screen. A 12.9s timeline plays the app in
  use: banners arrive as friends trade places, a cursor opens the board, you pass
  mvanhorn live (counts tick, the rank flips, contribution squares burst from the item),
  then the board closes. It starts on the open board, pauses off screen and with the
  shared pause control, and shows the final board for reduced motion. Behind it, a WebGL
  field of contribution squares lit after raycast.com's hero (`components/SquareField.tsx`);
  five variants are under review behind a temporary switcher (keys 1–6, `?bg=`).
- Lime `#C8FF2E` on near-black `#050505`, white type. Contribution-square ramp:
  `#14170F → #1D2E0E → #355C12 → #6AA81A → #C8FF2E`.
- Inter Tight for marketing text; native system typography inside the app mockups.
- Lead with friendly competition among friends; teammates are a secondary audience.
  Describe GitHub contributions rather than commits, output, or work performance.
- App mockups (hero popover, menu bar, notifications, connect sheet) follow the real
  SwiftUI app. Preserve native blue selection and You/Hidden labels in them. Notification text must match `NotificationService.copy(for:)`.
- Avatars and handles in the demo were approved for public use. Counts are a static
  public-data snapshot; animation frames illustrate rank changes rather than replaying
  recorded events. See the demo notes in [README.md](README.md).
- Keep global `text-pretty`, reduced-motion handling, and the shared pause control.

## Build and deployment

Use Node 22 and `npm ci`; `npm run build` exports the site to `out/`. Production is
[gitcommitted.app](https://gitcommitted.app), deployed by Vercel from
`prompthunt/committed`, branch `main`, root `site`. Cloudflare manages DNS.
Leave Vercel's Output Directory override unset. PNG response headers for extensionless
images are in `vercel.json`; `_headers` supports local/legacy Pages previews.

After changes, check desktop and mobile wrapping, motion controls, generated share
images, metadata, download links, and missing-route behavior. The app previews retain
native colors; the decorative mockups are excluded from the marketing accessibility
scope. Do not describe that scoped check as a blanket accessibility certification.

The download remains the stable `Committed.dmg` asset in the separate releases repo.
Website changes do not publish a native app release. Do not move the Xcode project or
change update identifiers. Keep account notes and deployment credentials outside Git.
