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
