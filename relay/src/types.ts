/** ContributionWindow raw values, shared with the Swift app. */
export type ContributionWindow = "daily" | "weekly" | "monthly";

export const WINDOWS: readonly ContributionWindow[] = ["daily", "weekly", "monthly"];

export const WINDOW_DAY_COUNT: Record<ContributionWindow, number> = {
  daily: 1,
  weekly: 7,
  monthly: 30,
};

/** Per-day contribution counts keyed by calendar date (`YYYY-MM-DD`). */
export type ContributionDays = Record<string, number>;
