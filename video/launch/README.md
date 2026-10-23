# Committed — 15-second launch film

A [HyperFrames](https://hyperframes.heygen.com) composition: HTML, a canvas, and one seekable
GSAP timeline, rendered to MP4. The rendered film is `renders/committed-launch.mp4`
(1920×1080, 60 fps, 15.000 s, H.264 + AAC).

## The cut

128 BPM: a three-beat pickup, six full bars, and a five-beat end card make exactly 32 beats,
or 15.000 s. `timing.js` holds that grid, and both the picture and the score read it, so every
cut and hit stays on the beat.

| Bars | Time | Shot |
|---|---|---|
| 1–2 | 0.00–2.81 | One lime square lands, the camera pulls back, and a year of contributions ripples in. "Who shipped more today?" |
| 2–4 | 2.81–7.03 | The year falls away. Today's square flies up and becomes the menu-bar rank. The popover opens and the board races: #3 → #1 → #2 → #1. |
| 5 | 7.03–8.91 | Rack focus to the real notification copy, stacked: "mvanhorn passed you", then "You passed mvanhorn!" |
| 6 | 8.91–10.78 | Hard cut. Today → 7 days → 30 days. The count rolls 223 → 2,072 → 5,917 while the window lights up on the year strip. |
| 7 | 10.78–12.66 | The year's squares lift off and build the trophy from its base up. |
| 8 | 12.66–15.00 | Impact. The pixel trophy sharpens (R → 2R → 4R), hands off to the vector mark, and pulls back into the app icon and end card. |

Every square on screen is one canvas "cell engine" driven by `frame(t)`, a pure function
of time. The same 368 days (52 weeks plus Sun–Wed) are the opening graph, the window strip,
and the trophy. The trophy pixels are sampled from the brand glyph path with
`isPointInPath`, so the silhouette is the real mark at every resolution.

Counts, handles, avatars, and notification copy come from the site's demo board
(`site/lib/board.ts`). Earlier frames show illustrative lead changes, and the film ends
on the verified counts.

## Work on it

```bash
cd video/launch
node scripts/score.mjs                                # re-synthesize assets/score.wav (no dependencies)
npx hyperframes preview --background                  # Studio preview
npx hyperframes check .                               # lint, runtime, layout, motion, contrast
npx hyperframes snapshot --at 2.6,5,8,10.1,12.6,14.6  # frames to look at
npx hyperframes render . -f 60 -q high -o renders/committed-launch-master.mp4
# web copy for the repo (the ~23 MB master stays local and is gitignored)
ffmpeg -i renders/committed-launch-master.mp4 -c:v libx264 -preset slow -crf 21 \
  -pix_fmt yuv420p -c:a copy -movflags +faststart renders/committed-launch.mp4
```

The score is synthesized from scratch in `scripts/score.mjs`: kick, clap, hats, sidechained
supersaw pads, offbeat bass, FM bells, risers, and a Freeverb-style reverb, with every
sound-design hit placed from `timing.js` cues. Change a cue there and the picture and the
score move together.

Fonts: Inter Tight (SIL OFL, `assets/fonts/OFL.txt`). Mac UI text uses the system font.
