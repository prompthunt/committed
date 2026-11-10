// Same raw values as the Mac and iPhone for 30 days ("monthly") and This month ("month").
export type Window = "today" | "week" | "monthly" | "month";
export interface Person {
  login: string;
  name: string | null;
  avatar_url: string | null;
  following?: boolean;
  organizations?: string[];
}
export interface Row extends Person {
  rank: number;
  contributions: number | null;
  /** Consecutive days with a contribution, alive through today; null before the calendar loads. */
  streak: number | null;
  is_you: boolean;
  movement: number;
  status: "loaded" | "loading" | "cached" | "failed" | "missing";
  /** Only on Final standings rows: ranks 1–3 of a finished month whose total was above zero. */
  medal?: Medal | null;
}
export type Medal = "gold" | "silver" | "bronze";
/** A finished month's ranks among the people on the board now; rows carry the month's total. */
export interface FinalStandings {
  /** The month's 1st, "2026-10-01". */
  month: string;
  /** "October", for "October final". */
  month_name: string;
  rows: Row[];
}
export interface Board {
  window: Window;
  rows: Row[];
  owner: string | null;
  refreshing: boolean;
  last_updated: number | null;
  error: string | null;
  people_updated: number | null;
  people_error: string | null;
  /** Today's day of the local month and the month's length: This month's "Day 10 of 30". */
  day_of_month: number;
  days_in_month: number;
  /** Last month's Final standings, all day on the 1st; null on other days. */
  final_standings: FinalStandings | null;
}
export interface Settings {
  notifications: boolean;
  automatic_updates: boolean;
  private_tip_dismissed: boolean;
}
export interface DesktopSettings {
  launch_at_login: boolean;
  version: string;
}
export interface PersonVisibility {
  person: Person;
  hidden: boolean;
  is_you: boolean;
}
