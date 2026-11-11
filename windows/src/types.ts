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
  /** The window's trolling day, if any: far above their usual, so the row wears the troll face. */
  burst?: Burst | null;
}
export interface Burst {
  date: string;
  count: number;
  /** Their usual big day before it: the count 9 in 10 of their earlier active days stay under. */
  usual: number;
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
/** One person's view (`get_person`): their month day by day beside last month's. */
export interface PersonView extends Person {
  is_you: boolean;
  status: Row["status"];
  /** This month's 1st, "2026-11-01", and its name, "November". */
  month: string;
  month_name: string;
  /** Last month's 1st and name: the grey bars. */
  last_month: string;
  last_month_name: string;
  day_of_month: number;
  days_in_month: number;
  /** Null until this person's calendar loads: the view waits instead of drawing zeros. */
  history: PersonHistory | null;
  /** Your race with them, on a rival's view once both calendars load; null on your own. */
  race: Race | null;
}
export type Side = "you" | "them";
/** How a race went, told by its lead (the core's `history::RaceStory`). */
export type RaceStory =
  | { kind: "level" }
  | { kind: "led"; by: Side }
  | { kind: "pulled_ahead"; by: Side; day: number }
  | { kind: "passed"; by: Side; day: number; changes: number }
  | { kind: "caught"; by: Side; day: number };
/** You against a rival over one month: this month so far, or on the 1st last month's final. */
export interface Race {
  month: string;
  month_name: string;
  is_final: boolean;
  /** Running totals from the 1st, one per day. */
  yours: number[];
  theirs: number[];
  story: RaceStory;
}
export interface PersonHistory {
  /** Each day's count from the 1st through today. */
  this_month: number[];
  /** Each day's count for every day of last month. */
  last_month: number[];
  current_streak: number;
  longest_streak: number;
  /** Days this month with a contribution: "Active days: 18 of 22". */
  active_days: number;
  /** Finished months, newest first. */
  finishes: MonthFinish[];
}
export interface MonthFinish {
  month: string;
  month_name: string;
  rank: number;
  of: number;
  total: number;
  medal: Medal | null;
  /** Where you finished that month, on a rival's view; null on your own. */
  your_rank: number | null;
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
