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
  is_you: boolean;
  movement: number;
  status: "loaded" | "loading" | "cached" | "failed" | "missing";
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
