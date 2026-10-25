"use client";

import { useState } from "react";
import { GitHubMark } from "../FeatureGrid";
import { seeded } from "@/lib/contributions";
import { WINDOW_COUNTS, board } from "@/lib/board";

export const PERIODS = ["Today", "7 days", "30 days"] as const;
export const PERIOD_DESCRIPTIONS = ["Today", "Past 7 days", "Past 30 days"] as const;
export const PERIOD_DAYS = [1, 7, 30] as const;

/** Time-frame selection shared by every variant's interactive demo. */
export function usePeriod() {
  const [selected, setSelected] = useState(0);
  return { selected, setSelected, total: WINDOW_COUNTS[selected], days: PERIOD_DAYS[selected] };
}

/**
 * Thirty decorative daily totals that add up to the verified window totals:
 * the last day is Today, the last seven sum to 7 days, all thirty sum to 30 days.
 * The per-day split is illustrative; only the three totals come from the snapshot.
 */
export const DAILY: number[] = (() => {
  const rnd = seeded(23);
  const spread = (n: number, total: number) => {
    const w = Array.from({ length: n }, (_, i) => 0.35 + rnd() + (i % 7 === 5 || i % 7 === 6 ? -0.25 : 0));
    const sum = w.reduce((a, b) => a + b, 0);
    const out = w.map((x) => Math.round((x / sum) * total));
    out[n - 1] += total - out.reduce((a, b) => a + b, 0);
    return out;
  };
  const [today, week, month] = WINDOW_COUNTS;
  return [...spread(23, month - week), ...spread(6, week - today), today];
})();

/** Contribution-square level (0–4) for a daily total, relative to the busiest day. */
export const dayLevel = (n: number) => {
  const f = n / Math.max(...DAILY);
  return f < 0.12 ? 0 : f < 0.35 ? 1 : f < 0.6 ? 2 : f < 0.85 ? 3 : 4;
};

/** Real commit subjects from the public repository. */
export const COMMITS = [
  ["4e87999", "Build the eight-card marketing feature grid"],
  ["fe0cbc7", "Spotlight hero backdrop and contribution strip"],
  ["6e6929c", "Bump version to 0.1.50 (52)"],
  ["13105c4", "Add a 15-second launch film for Committed"],
  ["6a81e4d", "Say “Connect GitHub” instead of “Sign in”"],
  ["64eeb28", "Track website download clicks and link public source"],
  ["5fff67e", "Initial open-source release of Committed"],
] as const;

/** Rank history for the three leaders across the demo loop (for bump charts). */
export function rankHistory() {
  const frames = [0, 1, 2, 3].map((f) => board(f).rows);
  const handles = ["addisonk", "mvanhorn", "jamielottering"];
  return handles.map((handle) => ({
    handle,
    you: handle === "addisonk",
    ranks: frames.map((rows) => rows.find((r) => r.handle === handle)!.rank),
  }));
}

/* 5×7 dot-matrix glyphs; "#" marks a lit square. */
export const PIXEL_FONT: Record<string, string[]> = {
  "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
  "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
  "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
  "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
  "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
  "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
  "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
  "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
  "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
  "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
  "#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
};

export const PIXEL_LOCK = [
  "..#####..",
  ".##...##.",
  ".#.....#.",
  ".#.....#.",
  "#########",
  "####.####",
  "###...###",
  "####.####",
  "####.####",
  "#########",
];

export const PIXEL_COMMAND = [
  ".##...##.",
  "#..#.#..#",
  "#..#.#..#",
  ".#######.",
  "...#.#...",
  ".#######.",
  "#..#.#..#",
  "#..#.#..#",
  ".##...##.",
];

/** Join glyphs side by side with one blank column between them. */
export function pixelText(text: string) {
  const glyphs = [...text].map((c) => PIXEL_FONT[c]);
  return glyphs[0].map((_, row) => glyphs.map((g) => g[row]).join("."));
}

/** A decorative crop of the app's first-run connection screen. */
export function ConnectSheet({ className = "" }: { className?: string }) {
  return (
    <div
      aria-hidden
      className={`font-mac flex w-[268px] max-w-full flex-col items-center rounded-[17px] border border-mac-border bg-mac-panel px-[22px] pt-[18px] pb-4 text-white ${className}`}
    >
      <GitHubMark className="mb-1.5 size-[27px]" />
      <strong className="text-sm font-semibold">Committed</strong>
      <span className="mt-3 mb-2 flex w-full items-center justify-center gap-[7px] rounded-lg bg-white px-1 py-[9px] text-xs font-semibold text-[#111]">
        <GitHubMark className="size-3.5" />
        Connect GitHub
      </span>
      <span className="text-[11px] leading-tight text-[#b1b1b8]">Committed never sees your code.</span>
    </div>
  );
}
