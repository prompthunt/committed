// Made-up board data for the dev fixture page (`fixture.html`) and the UI tests: the Sample
// board's people and counts (`CommitStandingsiOS/App/SampleServices.swift`), with streaks that
// cover every display case. Never read by the shipped app.
import type { Board, PersonVisibility, Row, Window } from "./types";

interface SamplePerson {
  login: string;
  name: string | null;
  counts: Record<Window, number> | null;
  streak: number | null;
  movement?: number;
}
export const samplePeople: SamplePerson[] = [
  // GitHub's calendar is 371 days long here, so the streak reads "365+".
  {
    login: "ines-volk",
    name: "Ines Volk",
    counts: { today: 12, week: 61, month: 240 },
    streak: 371,
  },
  {
    login: "odile-m",
    name: "Odile M.",
    counts: { today: 9, week: 44, month: 198 },
    streak: 23,
  },
  {
    login: "ari-linden",
    name: "Ari Linden",
    counts: { today: 7, week: 38, month: 171 },
    streak: 12,
    movement: 1,
  },
  {
    login: "ezra-q",
    name: "Ezra Q.",
    counts: { today: 6, week: 52, month: 160 },
    streak: 2,
    movement: -1,
  },
  // Nothing today, something yesterday: a 1-day streak, which isn't shown.
  {
    login: "bram-ott",
    name: "Bram Ott",
    counts: { today: 0, week: 11, month: 57 },
    streak: 1,
  },
  // Never loads: no count and no streak.
  { login: "niko-vane", name: "Niko Vane", counts: null, streak: null },
];
export const sampleOwner = "ari-linden";

/** The board the core would send for `window`, ranked like `committed_core::order`. */
export function sampleBoard(window: Window, now: number): Board {
  const rows: Row[] = samplePeople
    .map((person, index) => ({ person, index }))
    .sort(
      (a, b) =>
        (b.person.counts?.[window] ?? -1) - (a.person.counts?.[window] ?? -1) ||
        a.index - b.index,
    )
    .map(({ person }, index) => ({
      login: person.login,
      name: person.name,
      avatar_url: null,
      rank: index + 1,
      contributions: person.counts?.[window] ?? null,
      streak: person.streak,
      is_you: person.login === sampleOwner,
      movement: window === "today" ? (person.movement ?? 0) : 0,
      status: person.counts ? "loaded" : "failed",
    }));
  return {
    window,
    rows,
    owner: sampleOwner,
    refreshing: false,
    last_updated: now - 120,
    error: null,
    people_updated: now - 600,
    people_error: null,
  };
}

export const samplePeopleList = (): PersonVisibility[] =>
  samplePeople.map(({ login, name }) => ({
    person: { login, name, avatar_url: null },
    hidden: false,
    is_you: login === sampleOwner,
  }));
