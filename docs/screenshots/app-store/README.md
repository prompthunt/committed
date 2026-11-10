# App Store screenshots

The six 6.9" iPhone frames (1320 × 2868 px) for Committed's App Store listing (app 6831797452,
en-US). The app is iPhone only, so this one set covers every iPhone, iPhone Duo included.

| File | Caption |
|---|---|
| `01-board.png` | Who shipped more today? |
| `02-live-rank.png` | Your rank on the Lock Screen. |
| `03-widgets.png` | The board on your Home Screen. |
| `04-iphone-duo.png` | Open it up. See it all. |
| `05-share-board.png` | Share the board as an image. |
| `06-people.png` | Choose who's on your board. |

They're made in the screenshot editor, [`appstore/screenshots/`](../../../appstore/screenshots/README.md):
the deck is `app-store-screenshots.json`, and its README lists every source.

- **Five iPhone screens are renders, not runtime captures.** `AppStoreScreenshotTests` draws them
  from the Sample board at 440 × 956 pt, 3x, because the only Simulator on iOS 27.1 (the iPhone
  Duo) isn't an App Store size. Board, Share board and People are the real app in a window; Live
  rank and the widgets are the real views on a drawn Lock Screen and Home Screen.
- **The iPhone Duo screen is a runtime capture** of the Board open on the iPhone Duo Simulator,
  placed in Apple's Duo bezel.
- Every person is a sample person, avatars are initials, and nothing is fetched.

## Regenerate

1. Render the iPhone screens and copy them into the editor (04 is the Duo slide):

   ```sh
   TEST_RUNNER_RENDER_DIR="$PWD/build/app-store" \
     python3 scripts/ios_check.py ios --only-testing CommitStandingsiOSTests/AppStoreScreenshotTests
   S=appstore/screenshots/public/screenshots/apple/iphone/en
   cp build/app-store/screens/01-board.png $S/01.png
   cp build/app-store/screens/02-live-rank.png $S/02.png
   cp build/app-store/screens/03-widgets.png $S/03.png
   cp build/app-store/screens/04-share-board.png $S/05.png
   cp build/app-store/screens/05-people.png $S/06.png
   ```

2. Only when the Board changes, recapture the Duo. Open the iPhone Duo simulator in Device Hub
   (the **Open** pose: `simctl` can't fold it), then inside the `apple-session` lease install the
   Debug app and capture its inner display:

   ```sh
   xcrun simctl launch 94D56458-B90B-484A-BA5E-16748D2CBEE5 com.addisonk.CommitStandings.iOS \
     -ScreenshotFixture -ScreenshotHide niko-vane -dismissedPrivateContribTip YES
   xcrun simctl io 94D56458-B90B-484A-BA5E-16748D2CBEE5 screenshot --display=primary-1 \
     appstore/screenshots/public/screenshots/apple/duo/inner.png
   (cd appstore/screenshots && node scripts/frame-duo.mjs)
   ```

3. Export from the editor and copy the 1320 × 2868 PNGs here under these names:

   ```sh
   cd appstore/screenshots && bun dev --port 3477 &
   node scripts/export.mjs http://localhost:3477 export
   ```

Look at each PNG before committing, then set `sourceCommit` in `manifest.json` to the commit the
deck came from and run `python3 scripts/screenshot_evidence.py --base origin/main`.

## Upload

Upload to a version that's still being prepared: App Store Connect locks a version's screenshots
while it's in review and after approval. Upload only the PNGs, in file-name order, replacing the 6.9" set. `asc`
sends 6.9" to App Store Connect as `APP_IPHONE_67`; that's expected.

```sh
mkdir -p build/app-store-upload && cp docs/screenshots/app-store/0*.png build/app-store-upload/
asc screenshots validate --path build/app-store-upload --device-type IPHONE_69
asc screenshots upload --app 6831797452 --version <version> --locale en-US \
  --path build/app-store-upload --device-type IPHONE_69 --replace --confirm
asc screenshots list --app 6831797452 --version <version> --locale en-US
```
