# Marketing site design and maintenance

The static site lives in `site/`, alongside the native Xcode project. Build and
verification commands are in [README.md](README.md).

## Design decisions

- One hero, a contribution strip, and an eight-card feature grid. Keep the page short;
  do not add sections, pricing, testimonials, or extra copy without agreement.
- The approved wide-anchor grid has two large cards (GitHub connection and rank
  notifications), two medium cards (friends/teammates and time frames), and four
  compact cards (privacy, menu-bar rank, open source, and native macOS). Small
  cards use a short label and one visual. Medium/large cards use centered content,
  padding, and inner maximum widths so app previews do not stretch to fill a tile.
- The notification card has a Mac menu bar flush with its top edge, a demo clock,
  translucent glass banners underneath on the right, and a bottom-aligned caption.
  The desktop grid fills the existing 1,240px container; smaller screens reflow it.
- The hero popover sits under a lime spotlight: a beam from above, a pool of light
  below, and drifting dust (`components/HeroBackdrop.tsx`, `.bd-spot-*` in
  `globals.css`). The contribution squares live in the full-bleed strip that
  separates the hero from the feature grid (`components/ContributionStrip.tsx`).
- Lime `#C8FF2E` on near-black `#050505`, white type. Contribution-square ramp:
  `#14170F → #1D2E0E → #355C12 → #6AA81A → #C8FF2E`.
- Inter Tight for marketing text; native system typography inside the app mockups.
- Lead with friendly competition among friends; teammates are a secondary audience.
  Describe GitHub contributions rather than commits, output, or work performance.
- Mockups follow the real SwiftUI app. Preserve native blue selection and You/Hidden
  labels. Notification text must match `NotificationService.copy(for:)`.
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
