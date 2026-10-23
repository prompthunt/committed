// One beat grid for picture and sound. index.html loads this as a classic script;
// scripts/score.mjs imports it after defining a global `window`.
// 128 BPM: bar 1 is a three-beat pickup, bars 2–7 are full, and bar 8 (the end card)
// rings for five beats, so the film is 32 beats = exactly 15.000 s.
(function () {
  const BPM = 128;
  const BEAT = 60 / BPM; // 0.46875 s
  const BAR = BEAT * 4; // 1.875 s
  const PICKUP = BEAT; // bar 1's first beat falls before the film starts
  /** Time of bar `bar` (1-based), beat `beat` (1-based), plus `frac` beats. */
  const at = (bar, beat = 1, frac = 0) => (bar - 1) * BAR + (beat - 1 + frac) * BEAT - PICKUP;

  window.TIMING = {
    BPM,
    BEAT,
    BAR,
    DURATION: 15,
    at,
    cue: {
      seed: at(1, 3), // first square lands
      ripple: at(1, 4), // camera pulls back, the year fills in
      drop: at(2, 1), // beat drops, headline
      collapse: at(2, 4), // the year falls away
      flight: at(2, 4, 0.25), // today's square flies to the menu bar
      board: at(3, 1), // square lands as the menu-bar rank
      click: at(3, 2), // popover opens
      climb1: at(3, 3), // you pass jamielottering and mvanhorn
      passed: at(4, 1), // mvanhorn passes you
      climb2: at(4, 3), // you pass mvanhorn for good
      nudge: at(5, 1), // notification hero
      nudge2: at(5, 2),
      windows: at(6, 1), // Today
      week: at(6, 2), // 7 days
      month: at(6, 3), // 30 days
      build: at(7, 1), // squares assemble the trophy
      gap: at(7, 4), // music drops out
      impact: at(8, 1), // logo resolve
    },
    /** Every kick: four on the floor from bar 2 through bar 7 beat 3. */
    kicks: (() => {
      const out = [];
      for (let bar = 2; bar <= 7; bar++)
        for (let beat = 1; beat <= 4; beat++) if (!(bar === 7 && beat === 4)) out.push(at(bar, beat));
      return out;
    })(),
  };
})();
