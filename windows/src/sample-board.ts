// Made-up board data for the dev fixture page (`fixture.html`) and the UI tests: the Sample
// board's people and counts (`CommitStandingsiOS/App/SampleServices.swift`), with streaks that
// cover every display case. Never read by the shipped app.
import type {
  Board,
  FinalStandings,
  PersonVisibility,
  Row,
  Window,
} from "./types";

interface SamplePerson {
  login: string;
  name: string | null;
  counts: Record<Window, number> | null;
  streak: number | null;
  movement?: number;
  /** Last month's total, for Final standings on the 1st. */
  lastMonth: number | null;
}
export const samplePeople: SamplePerson[] = [
  // GitHub's calendar is 371 days long here, so the streak reads "365+".
  {
    login: "ines-volk",
    name: "Ines Volk",
    counts: { today: 12, week: 61, monthly: 240, month: 224 },
    streak: 371,
    lastMonth: 212,
  },
  {
    login: "odile-m",
    name: "Odile M.",
    counts: { today: 9, week: 44, monthly: 198, month: 185 },
    streak: 23,
    lastMonth: 160,
  },
  {
    login: "ari-linden",
    name: "Ari Linden",
    counts: { today: 7, week: 38, monthly: 171, month: 160 },
    streak: 12,
    movement: 1,
    // Ties odile-m last month: you win ties, so you take silver.
    lastMonth: 160,
  },
  {
    login: "ezra-q",
    name: "Ezra Q.",
    counts: { today: 6, week: 52, monthly: 160, month: 149 },
    streak: 2,
    movement: -1,
    lastMonth: 98,
  },
  // Nothing today, something yesterday: a 1-day streak, which isn't shown.
  {
    login: "bram-ott",
    name: "Bram Ott",
    counts: { today: 0, week: 11, monthly: 57, month: 50 },
    streak: 1,
    // Nothing last month: no medal, whatever the rank.
    lastMonth: 0,
  },
  // Never loads: no count and no streak.
  {
    login: "niko-vane",
    name: "Niko Vane",
    counts: null,
    streak: null,
    lastMonth: null,
  },
];
export const sampleOwner = "ari-linden";

/** Ranked like `committed_core::order`: count descending, no count last, you first on ties. */
function ranked(count: (person: SamplePerson) => number | null) {
  return samplePeople
    .map((person, index) => ({ person, index }))
    .sort(
      (a, b) =>
        (count(b.person) ?? -1) - (count(a.person) ?? -1) ||
        Number(b.person.login === sampleOwner) -
          Number(a.person.login === sampleOwner) ||
        a.index - b.index,
    )
    .map(({ person }) => person);
}

/** Last month's Final standings, like the core's `final_standings`: medals for ranks 1–3 above 0. */
function sampleFinalStandings(date: Date): FinalStandings {
  const month = new Date(date.getFullYear(), date.getMonth() - 1, 1);
  const medals = ["gold", "silver", "bronze"] as const;
  return {
    month: `${month.getFullYear()}-${String(month.getMonth() + 1).padStart(2, "0")}-01`,
    month_name: month.toLocaleString("en-US", { month: "long" }),
    rows: ranked((person) => person.lastMonth).map((person, index) => ({
      login: person.login,
      name: person.name,
      avatar_url: null,
      rank: index + 1,
      contributions: person.lastMonth,
      streak: null,
      is_you: person.login === sampleOwner,
      movement: 0,
      status: person.lastMonth === null ? "missing" : "loaded",
      medal: person.lastMonth ? (medals[index] ?? null) : null,
    })),
  };
}

/** The board the core would send for `window`, ranked like `committed_core::order`. */
export function sampleBoard(window: Window, now: number): Board {
  // The core sends today's local day of the month and the month's length (This month's "Day X of Y").
  const date = new Date(now * 1000);
  const rows: Row[] = ranked((person) => person.counts?.[window] ?? null).map(
    (person, index) => ({
      login: person.login,
      name: person.name,
      avatar_url: null,
      rank: index + 1,
      contributions: person.counts?.[window] ?? null,
      streak: person.streak,
      is_you: person.login === sampleOwner,
      movement:
        window === "today" || window === "month" ? (person.movement ?? 0) : 0,
      status: person.counts ? "loaded" : "failed",
    }),
  );
  return {
    window,
    rows,
    owner: sampleOwner,
    refreshing: false,
    last_updated: now - 120,
    error: null,
    people_updated: now - 600,
    people_error: null,
    day_of_month: date.getDate(),
    days_in_month: new Date(
      date.getFullYear(),
      date.getMonth() + 1,
      0,
    ).getDate(),
    final_standings: date.getDate() === 1 ? sampleFinalStandings(date) : null,
  };
}

export const samplePeopleList = (): PersonVisibility[] =>
  samplePeople.map(({ login, name }) => ({
    person: { login, name, avatar_url: null },
    hidden: false,
    is_you: login === sampleOwner,
  }));
