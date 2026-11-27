# Top-3 trophies

The gold, silver and bronze trophies on the iPhone hero card (`BoardSummaryView`) when you're 1st,
2nd or 3rd on a board of at least four people. They appear only there, so they stay special.

- **Source:** generated with fal's `openai/gpt-image-2.6/flare/text-to-image`, `background: transparent`,
  by `scripts/trophy-artwork.py`, then refined with the same model: the embossed numeral became a rank
  chevron and gem, and cat ears were added to the rim (the app icon's ears). The script's prompt describes
  the refined cup, so a fresh run lands close to the shipped art but won't match it pixel for pixel. The
  prompt and settings are frozen so the three places match; change them only to regenerate the whole set.
- **`masters/`:** the 1024 px transparent originals, lossless WebP.
- **Bundled:** `CommitStandingsiOS/Assets.xcassets/Trophy{Gold,Silver,Bronze}.dataset`, 512 px WebP with
  alpha, loaded through `NSDataAsset`. There are no runtime network calls.
- **Regenerate:** `scripts/trophy-artwork.py plan`, then `run --out DIR` (about $0.15; needs `FAL_KEY` in the
  environment), look at the results, then `publish --from DIR`. Never put `FAL_KEY` on a command line or in git.

The metal frame and the soft wash of light on the podium card (`CardChrome`, `Podium.metal` in
`BoardSummaryView.swift`) are drawn in SwiftUI, not part of the art.
