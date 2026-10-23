/** Seeded PRNG so decorative contribution data renders identically on server and client. */
export function seeded(seed: number) {
  return () => ((seed = (seed * 9301 + 49297) % 233280), seed / 233280);
}

/** Contribution-square ramp, darkest to lime. */
export const SQUARE_SCALE = [
  "var(--color-sq-0)",
  "var(--color-sq-1)",
  "var(--color-sq-2)",
  "var(--color-sq-3)",
  "var(--color-lime)",
] as const;

/**
 * A wide contribution calendar: `weeks` columns of 7 days. Weekends run lighter, activity
 * builds from left to right, and a few streaks burn hot so it reads like a real year.
 */
export function contributionYear(weeks: number, seed = 7): number[][] {
  const rnd = seeded(seed);
  const streaks = new Set<number>();
  for (let i = 0; i < Math.round(weeks / 9); i++) streaks.add(Math.floor(rnd() * weeks));

  return Array.from({ length: weeks }, (_, w) => {
    const build = (w / weeks) * 0.4;
    const hot = streaks.has(w) || streaks.has(w - 1) ? 0.3 : 0;
    return Array.from({ length: 7 }, (_, d) => {
      const weekend = d === 0 || d === 6 ? -0.28 : 0;
      const x = rnd() * 0.8 + build + hot + weekend;
      return x < 0.4 ? 0 : x < 0.64 ? 1 : x < 0.88 ? 2 : x < 1.08 ? 3 : 4;
    });
  });
}
