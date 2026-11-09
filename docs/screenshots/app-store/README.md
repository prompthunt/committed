# App Store screenshots

The five 6.9" iPhone frames (1320 × 2868 px) on the App Store listing for Committed 1.0
(app 6831797452, en-US). The app is iPhone only, so this one set covers every iPhone.

| File | Caption |
|---|---|
| `01-board.png` | Who shipped more today? Friends ranked by GitHub contributions. |
| `02-live-rank.png` | Your rank on the Lock Screen. See who's ahead and how many to pass. |
| `03-widgets.png` | The board on your Home Screen. Your rank and the leaders at a glance. |
| `04-share-board.png` | Share the board as an image. A square post or a story. |
| `05-people.png` | Choose who's on your board. From who you follow and your organizations. |

They're renders, not runtime captures. `AppStoreScreenshotTests` draws them from the Sample board at
440 × 956 pt, 3x, because the only Simulator on iOS 27.1 (the iPhone Duo) isn't an App Store size.
Board, Share board and People are the real app in a window; Live rank and the widgets are the real
views on a drawn Lock Screen and Home Screen. The captions, layout and phone live in
`CommitStandingsiOSTests/AppStoreScreenshots.swift`.

The frames leave out the "Sample board · Connect GitHub" banner: the test runs the Sample board's
services as the app's graph, so the app shows them as a connected board. Nothing in the app changes
for it. Every person is a sample person, avatars are initials, and nothing is fetched.

## Regenerate

```sh
TEST_RUNNER_RENDER_DIR="$PWD/build/app-store" \
  python3 scripts/ios_check.py ios --only-testing CommitStandingsiOSTests/AppStoreScreenshotTests
cp build/app-store/0*.png docs/screenshots/app-store/
```

Look at each PNG before committing, then set `sourceCommit` in `manifest.json` to the commit the
renders came from and run `python3 scripts/screenshot_evidence.py --base origin/main`.

## Upload

Upload only the PNGs, in file-name order, replacing the 6.9" set. `asc` sends 6.9" to App Store
Connect as `APP_IPHONE_67`; that's expected.

```sh
mkdir -p build/app-store-upload && cp docs/screenshots/app-store/0*.png build/app-store-upload/
asc screenshots validate --path build/app-store-upload --device-type IPHONE_69
asc screenshots upload --app 6831797452 --version 1.0 --locale en-US \
  --path build/app-store-upload --device-type IPHONE_69 --replace --confirm
asc screenshots list --app 6831797452 --version 1.0 --locale en-US
```

Then confirm `asc validate` no longer reports `screenshots.required.any`:

```sh
asc validate --app 6831797452 --version-id efad017c-5171-480c-b19e-f9c3548e521d --platform IOS --output table
```
