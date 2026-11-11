// Made-up board data for the dev fixture page (`fixture.html`) and the UI tests: the Sample
// board's people and counts (`CommitStandingsiOS/App/SampleServices.swift`), with streaks that
// cover every display case. Never read by the shipped app.
import type {
  Board,
  FinalStandings,
  Medal,
  MonthFinish,
  PersonView,
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

/** A made-up but repeatable number in [0, 1) for `login` and `n`, so the fixture never changes. */
function noise(login: string, n: number) {
  let hash = 2166136261 ^ n;
  for (const c of login) hash = Math.imul(hash ^ c.charCodeAt(0), 16777619);
  hash = Math.imul(hash ^ (hash >>> 15), 2246822507);
  return ((hash ^ (hash >>> 13)) >>> 0) / 2 ** 32;
}

/** `total` spread over the days marked active (weights from `noise`), whole numbers. */
function spread(
  login: string,
  salt: number,
  active: boolean[],
  total: number,
): number[] {
  const weights = active.map((on, i) =>
    on ? 0.2 + noise(login, salt + i) ** 2 : 0,
  );
  const sum = weights.reduce((a, b) => a + b, 0);
  if (!sum || total <= 0) return active.map(() => 0);
  const counts = weights.map((w) =>
    w ? Math.max(1, Math.floor((total * w) / sum)) : 0,
  );
  // Settle rounding on the heaviest day so the series adds up to `total`.
  const heaviest = weights.indexOf(Math.max(...weights));
  counts[heaviest] += total - counts.reduce((a, b) => a + b, 0);
  return counts;
}

/** The longest run of non-zero days in `series`. */
function longestRun(series: number[]) {
  let longest = 0;
  let run = 0;
  for (const count of series) {
    run = count > 0 ? run + 1 : 0;
    longest = Math.max(longest, run);
  }
  return longest;
}

const iso = (date: Date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
const monthName = (date: Date) =>
  date.toLocaleString("en-US", { month: "long" });

/**
 * The person view the core would send for a Sample person on the day `now` falls on: this
 * month's days add up to their This month count with today's count last and the current streak
 * ending today, last month's add up to last month's total, and six finished months with medals.
 * Niko never loads, so his view waits. Consistent on the 2nd to the 29th; made up all the same.
 */
export function samplePerson(login: string, now: number): PersonView | null {
  const person = samplePeople.find((p) => p.login === login);
  if (!person) return null;
  const date = new Date(now * 1000);
  const day = date.getDate();
  const month = new Date(date.getFullYear(), date.getMonth(), 1);
  const lastMonth = new Date(date.getFullYear(), date.getMonth() - 1, 1);
  const lastLength = new Date(date.getFullYear(), date.getMonth(), 0).getDate();
  const view: PersonView = {
    login,
    name: person.name,
    avatar_url: null,
    is_you: login === sampleOwner,
    status: person.counts ? "loaded" : "failed",
    month: iso(month),
    month_name: monthName(month),
    last_month: iso(lastMonth),
    last_month_name: monthName(lastMonth),
    day_of_month: day,
    days_in_month: new Date(
      date.getFullYear(),
      date.getMonth() + 1,
      0,
    ).getDate(),
    history: null,
  };
  if (!person.counts || person.streak === null) return view;
  const today = person.counts.today;
  const streak = person.streak;
  // The streak's run ends today, or yesterday when today has nothing yet.
  const runEnd = today > 0 ? day : day - 1;
  const runStart = runEnd - streak + 1;
  const active = Array.from({ length: day - 1 }, (_, i) => {
    const d = i + 1;
    if (d >= runStart && d <= runEnd) return true;
    if (d === runStart - 1) return false;
    return noise(login, d) < 0.72;
  });
  const thisMonth = [
    ...spread(login, 0, active, person.counts.month - today),
    today,
  ];
  // Last month: its days before this month's run are free; a run that reaches back stays whole.
  const carried = Math.max(0, streak - runEnd);
  const pastActive = Array.from({ length: lastLength }, (_, i) => {
    const d = i + 1;
    if (d > lastLength - carried) return true;
    if (carried && d === lastLength - carried) return false;
    return noise(login, 100 + d) < 0.68;
  });
  const lastMonthSeries = spread(login, 200, pastActive, person.lastMonth ?? 0);
  return {
    ...view,
    history: {
      this_month: thisMonth,
      last_month: lastMonthSeries,
      current_streak: streak,
      longest_streak: Math.max(
        streak,
        longestRun([...lastMonthSeries, ...thisMonth]),
        9 + Math.floor(noise(login, 999) * 20),
      ),
      active_days: thisMonth.filter((n) => n > 0).length,
      finishes: sampleFinishes(login, date),
    },
  };
}

/** Six finished months, newest first: last month's Final standings, then made-up earlier ones. */
function sampleFinishes(login: string, date: Date): MonthFinish[] {
  const medals: Medal[] = ["gold", "silver", "bronze"];
  return Array.from({ length: 6 }, (_, i) => {
    const month = new Date(date.getFullYear(), date.getMonth() - 1 - i, 1);
    const total = (person: SamplePerson) =>
      person.lastMonth === null
        ? null
        : i === 0
          ? person.lastMonth
          : Math.round(
              (person.counts?.monthly ?? 0) *
                (0.45 + noise(person.login, 500 + i)),
            );
    const order = ranked(total);
    const rank = order.findIndex((p) => p.login === login) + 1;
    const mine = total(order[rank - 1]) ?? 0;
    return {
      month: iso(month),
      month_name: monthName(month),
      rank,
      of: order.length,
      total: mine,
      medal: mine > 0 ? (medals[rank - 1] ?? null) : null,
    };
  });
}
