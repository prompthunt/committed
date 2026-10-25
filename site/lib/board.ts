// Demo data for the animated board. Handles and avatars are real (public use approved by the owner on 2026-10-22);
// The final frame and window totals are a public-calendar snapshot from 2026-10-22
// (America/Los_Angeles). Earlier frames illustrate rank changes, not recorded events.

export const DOWNLOAD_URL =
  "https://github.com/prompthunt/commit-standings-releases/releases/latest/download/Committed.dmg";
export const RELEASES_URL =
  "https://github.com/prompthunt/commit-standings-releases/releases/latest";
export const SOURCE_URL = "https://github.com/prompthunt/committed";

export const ME = { name: "Addison", handle: "addisonk", avatar: "/avatars/addisonk.png" };

type Person = { handle: string; you?: boolean };

export const PEOPLE: Person[] = [
  { handle: "mvanhorn" },
  { handle: "addisonk", you: true },
  { handle: "jamielottering" },
  { handle: "danielkinsner" },
  { handle: "jmzzll" },
  { handle: "kropdx" },
];

export const avatar = (handle: string) => `/avatars/${handle}.png`;

export const WINDOW_COUNTS = [223, 2072, 5917];

const TODAY_COUNTS = [124, WINDOW_COUNTS[0], 84, 47, 53, 24];
const jamie = TODAY_COUNTS[2];
const firstLead = jamie + 1;

/** Illustrative lead changes, ending on verified counts in PEOPLE order. */
const FRAMES: number[][] = [
  [jamie - 1, jamie - 4, ...TODAY_COUNTS.slice(2)],
  [jamie - 1, firstLead, ...TODAY_COUNTS.slice(2)],
  [TODAY_COUNTS[0], firstLead, ...TODAY_COUNTS.slice(2)],
  TODAY_COUNTS,
];
export const FRAME_COUNT = FRAMES.length;

/** The app's real notification copy (NotificationService.copy). */
const NOTES = [
  { title: "🎉 You passed jamielottering!", body: `You're ahead ${firstLead}–${jamie}. Keep climbing!`, at: 1 },
  { title: "😤 mvanhorn passed you", body: `They're ahead ${TODAY_COUNTS[0]}–${firstLead}. Time to catch up!`, at: 2 },
  { title: "🎉 You passed mvanhorn!", body: `You're ahead ${TODAY_COUNTS[1]}–${TODAY_COUNTS[0]}. Keep climbing!`, at: 3 },
];

const CHEVRON = {
  up1: "M6 15l6-6 6 6",
  up2: "M6 12l6-6 6 6M6 18l6-6 6 6",
  down1: "M6 9l6 6 6-6",
  down2: "M6 6l6 6 6-6M6 12l6 6 6-6",
};

export const fmt = (n: number) => n.toLocaleString("en-US");

function ranks(counts: number[]) {
  const order = counts.map((_, i) => i).sort((a, b) => counts[b] - counts[a]);
  const rankOf: number[] = [];
  order.forEach((idx, r) => (rankOf[idx] = r));
  return rankOf;
}

/** Contribution-square shade relative to the leader (mirrors ContributionShade in StandingRow.swift). */
function shade(value: number, max: number) {
  const f = max > 0 ? Math.min(1, value / max) : 0;
  const c = (lo: number, hi: number) => Math.round(lo + (hi - lo) * f);
  return `rgb(${c(155, 46)},${c(233, 160)},${c(168, 67)})`;
}

export function board(frame: number) {
  const p = ((frame % FRAME_COUNT) + FRAME_COUNT) % FRAME_COUNT;
  const counts = FRAMES[p];
  const rankOf = ranks(counts);
  const baseRank = ranks(FRAMES[0]);
  const max = Math.max(...counts);

  const rows = PEOPLE.map((person, i) => {
    const moved = baseRank[i] - rankOf[i];
    return {
      ...person,
      count: counts[i],
      rank: rankOf[i] + 1,
      chevron:
        moved > 1 ? CHEVRON.up2 : moved === 1 ? CHEVRON.up1 : moved === -1 ? CHEVRON.down1 : moved < -1 ? CHEVRON.down2 : "",
      chevronUp: moved > 0,
      square: shade(counts[i], max),
    };
  });

  const shown = NOTES.filter((n) => n.at <= p);
  const notes = NOTES.map((n) => {
    if (n.at > p) return { ...n, time: "now", state: "pending" as const };
    const age = shown.length - 1 - shown.indexOf(n);
    return { ...n, time: age === 0 ? "now" : `${age}m ago`, state: age === 0 ? ("top" as const) : age === 1 ? ("behind" as const) : ("gone" as const) };
  });

  const you = rows.find((r) => r.you)!;
  return { rows, notes, youRank: you.rank, youCount: you.count, synced: [3, 6, 9, 12][p] };
}
