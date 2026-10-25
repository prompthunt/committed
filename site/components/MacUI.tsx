"use client";

import { board, fmt, ME, avatar } from "@/lib/board";
import { useFrame } from "./useLoop";
import { Glyph } from "./Glyph";

/* Small pieces of the app's native UI, rebuilt in HTML. */

export function Dots() {
  return (
    <span aria-hidden className="flex gap-[3px]">
      <span className="size-[3px] rounded-full bg-[#98989d]" />
      <span className="size-[3px] rounded-full bg-[#98989d]" />
      <span className="size-[3px] rounded-full bg-[#98989d]" />
    </span>
  );
}

export function RankPill({ rank, className = "" }: { rank: number; className?: string }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full bg-white/15 font-semibold text-white backdrop-blur-xl ${className}`}
    >
      <Glyph className="size-[1.05em]" />#{rank}
    </span>
  );
}

/** The menu-bar item above the hero popover. */
export function HeroRankPill() {
  const b = board(useFrame());
  return <RankPill rank={b.youRank} className="px-3 py-[5px]" />;
}

function YouBadge() {
  return (
    <span className="rounded-full bg-mac-you-border px-[7px] py-px text-[11px] font-semibold text-mac-you-text">you</span>
  );
}

/** The real menu-bar popover: Today board, rows that reorder as the loop plays. */
export function Popover() {
  const b = board(useFrame());
  const ROW = 40;

  return (
    <div className="font-mac w-[340px] max-w-full overflow-hidden rounded-[22px] border border-mac-border bg-mac-panel shadow-[0_0_0_.5px_rgba(0,0,0,.8),0_40px_90px_-20px_rgba(0,0,0,.95)]">
      <div className="flex h-11 items-center justify-between border-b border-mac-divider px-4">
        <span className="text-[15px] font-bold">Committed</span>
        <Dots />
      </div>
      <div className="flex flex-col gap-2.5 px-3 pt-2.5 pb-3">
        <span className="px-1 text-[11px] text-mac-gray">Synced {b.synced} sec ago</span>
        <div className="flex items-center self-center rounded-lg bg-mac-control p-0.5 text-[13px]">
          <span className="rounded-md bg-mac-blue px-3.5 py-1 text-white">Today</span>
          <span className="px-3.5 py-1 text-mac-label">7 days</span>
          <span aria-hidden className="h-3 w-px bg-[#48484a]" />
          <span className="px-3 py-1 text-mac-label">30 days</span>
        </div>
        <div className="flex items-center gap-3 rounded-[14px] border border-mac-you-border bg-mac-you p-3.5">
          <img src={ME.avatar} alt="" className="size-[50px] shrink-0 rounded-full object-cover" />
          <span className="flex min-w-0 flex-1 flex-col leading-tight">
            <span className="text-sm font-bold">{ME.name}</span>
            <span className="text-sm font-semibold text-mac-gray">@{ME.handle}</span>
          </span>
          <span className="flex flex-col items-end">
            <span className="font-display text-[34px] leading-none font-extrabold tracking-[-0.04em] tabular-nums">
              {fmt(b.youCount)}
            </span>
            <span className="mt-1 text-[8px] font-semibold tracking-[.14em] text-[#aeaeb2]">CONTRIBUTIONS</span>
          </span>
        </div>
        <div className="flex justify-between px-2 pt-0.5 text-[11px] text-mac-gray">
          <span>Tracking {b.rows.length} people</span>
          <span>People…</span>
        </div>
        <ol className="relative" style={{ height: b.rows.length * ROW }}>
          {b.rows.map((r) => (
            <li
              key={r.handle}
              className={`absolute inset-x-0 top-0 flex h-[38px] items-center gap-2.5 rounded-[10px] border pr-3 pl-2 transition-transform duration-700 ease-[cubic-bezier(.2,.8,.2,1)] ${
                r.you ? "border-mac-you-border bg-mac-you" : "border-transparent"
              }`}
              style={{ transform: `translateY(${(r.rank - 1) * ROW}px)` }}
            >
              <span className="w-[26px] text-right text-xs text-mac-gray">#{r.rank}</span>
              <img src={avatar(r.handle)} alt="" className="size-[26px] shrink-0 rounded-full object-cover" />
              <span className={`flex min-w-0 flex-1 items-center gap-1.5 truncate text-sm ${r.you ? "font-bold" : "font-medium"}`}>
                {r.handle}
                {r.you && <YouBadge />}
              </span>
              <svg
                aria-hidden
                viewBox="0 0 24 24"
                className="mr-2.5 size-3.5 shrink-0"
                fill="none"
                stroke={r.chevronUp ? "var(--color-mac-green)" : "var(--color-mac-gray)"}
                strokeWidth={2.4}
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                {r.chevron && <path d={r.chevron} />}
              </svg>
              <span className="w-8 text-right text-sm font-semibold tabular-nums">{r.count}</span>
              <span aria-hidden className="ml-1 grid grid-cols-2 gap-[1.5px]">
                {[0, 1, 2, 3].map((k) => (
                  <span key={k} className="size-[5px] rounded-[1px]" style={{ background: r.square }} />
                ))}
              </span>
            </li>
          ))}
        </ol>
      </div>
    </div>
  );
}

/** macOS notification banners, newest on top, using the app's real copy. */
export function NotificationStack() {
  const b = board(useFrame());
  const pose = {
    pending: "opacity-0 -translate-y-6 scale-[.96] z-30",
    top: "opacity-100 translate-y-0 scale-100 z-30",
    behind: "opacity-100 translate-y-[78px] max-sm:translate-y-[90px] scale-[.95] z-20",
    gone: "opacity-0 translate-y-[70px] max-sm:translate-y-[96px] scale-90 z-10",
  } as const;

  return (
    <div aria-hidden className="font-mac relative h-[172px] w-full max-w-[340px] max-sm:h-[196px]">
      {b.notes.map((n) => (
        <div
          key={n.title}
          className={`notification-glass absolute inset-x-0 top-0 flex gap-3 rounded-[18px] border border-white/15 px-3.5 py-3 text-white shadow-[0_18px_40px_-16px_rgba(0,0,0,.7)] transition-[opacity,transform] duration-700 ease-[cubic-bezier(.16,1,.3,1)] ${pose[n.state]}`}
        >
          <span className="flex size-[34px] shrink-0 items-center justify-center rounded-[9px] bg-gradient-to-b from-[#1c1e1c] to-[#070807] shadow-[inset_0_0_0_1px_rgba(255,255,255,.1)]">
            <Glyph className="size-[21px] text-lime" />
          </span>
          <span className="flex min-w-0 flex-1 flex-col gap-px">
            <span className="flex justify-between gap-2 text-[13px] font-bold">
              <span className="truncate">{n.title}</span>
              <span className="shrink-0 text-[11px] font-normal text-mac-gray">{n.time}</span>
            </span>
            <span className="text-[13px] text-[#d9ddd4]">{n.body}</span>
          </span>
        </div>
      ))}
    </div>
  );
}
