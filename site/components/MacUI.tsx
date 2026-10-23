"use client";

import { board, fmt, ME, avatar, WINDOW_COUNTS } from "@/lib/board";
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
    behind: "opacity-55 translate-y-[58px] max-sm:translate-y-[84px] scale-[.95] z-20",
    gone: "opacity-0 translate-y-[70px] max-sm:translate-y-[96px] scale-90 z-10",
  } as const;

  return (
    <div aria-hidden className="font-mac relative h-[150px] w-full max-w-[340px] max-sm:h-[176px]">
      {b.notes.map((n) => (
        <div
          key={n.title}
          className={`absolute inset-x-0 top-0 flex gap-3 rounded-[18px] border border-white/10 bg-[rgba(30,30,32,.96)] px-3.5 py-3 text-white shadow-[0_18px_40px_-16px_rgba(0,0,0,.7)] transition-[opacity,transform] duration-700 ease-[cubic-bezier(.16,1,.3,1)] ${pose[n.state]}`}
        >
          <span className="flex size-[34px] shrink-0 items-center justify-center rounded-[9px] bg-gradient-to-b from-[#1c1e1c] to-[#070807] shadow-[inset_0_0_0_1px_rgba(255,255,255,.1)]">
            <Glyph className="size-[21px] text-lime" />
          </span>
          <span className="flex min-w-0 flex-1 flex-col gap-px">
            <span className="flex justify-between gap-2 text-[13px] font-bold">
              <span className="truncate">{n.title}</span>
              <span className="shrink-0 text-[11px] font-normal text-mac-gray">{n.time}</span>
            </span>
            <span className="text-[13px] text-[#c7c7cc]">{n.body}</span>
          </span>
        </div>
      ))}
    </div>
  );
}

/** Menu bar with the rank pill, plus the top of the popover dropping from it. */
export function MenuBarScene() {
  const b = board(useFrame());
  return (
    <div
      aria-hidden
      className="font-mac relative h-[200px] overflow-hidden bg-[radial-gradient(120%_120%_at_30%_0%,#23301a_0%,#0e100b_70%)] [mask-image:linear-gradient(#000_70%,transparent)]"
    >
      <div className="flex h-[30px] items-center justify-end gap-3.5 border-b border-white/5 bg-white/[.07] px-3 text-[13px] text-mac-label">
        <RankPill rank={b.youRank} className="bg-white/20 px-2.5 py-0.5" />
        <svg width="17" height="13" viewBox="0 0 17 13" fill="currentColor">
          <path d="M8.5 2.5c2.3 0 4.4.9 6 2.4l1.2-1.3C13.8 1.8 11.3.7 8.5.7S3.2 1.8 1.3 3.6l1.2 1.3c1.6-1.5 3.7-2.4 6-2.4zm0 3.5c1.4 0 2.6.5 3.6 1.4l1.2-1.3C12 4.9 10.3 4.2 8.5 4.2S5 4.9 3.7 6.1l1.2 1.3c1-.9 2.2-1.4 3.6-1.4zm0 3.4c.5 0 1 .2 1.3.5L8.5 11.3 7.2 9.9c.3-.3.8-.5 1.3-.5z" />
        </svg>
        <svg width="24" height="12" viewBox="0 0 24 12" fill="none">
          <rect x=".5" y=".5" width="20" height="11" rx="3" stroke="currentColor" />
          <rect x="2" y="2" width="14" height="8" rx="1.5" fill="currentColor" />
          <rect x="21.5" y="4" width="1.6" height="4" rx=".8" fill="currentColor" />
        </svg>
        <span>Wed 4:12 PM</span>
      </div>
      <div className="absolute top-[38px] right-[70px] w-[250px] overflow-hidden rounded-2xl border border-mac-border bg-mac-panel shadow-[0_20px_50px_-16px_rgba(0,0,0,.9)]">
        <div className="flex h-9 items-center justify-between border-b border-mac-divider px-3.5 text-[13px] font-bold">
          Committed
          <Dots />
        </div>
        <div className="px-3 py-2 text-[10px] text-mac-gray">Synced {b.synced} sec ago</div>
        <div className="mx-2.5 mb-2.5 flex items-center gap-2.5 rounded-[11px] border border-lime/35 bg-lime/[.07] p-2.5">
          <img src={ME.avatar} alt="" className="size-[30px] rounded-full object-cover" />
          <span className="flex-1 text-xs font-bold">@{ME.handle}</span>
          <span className="text-[22px] font-extrabold tracking-[-0.04em] tabular-nums">{fmt(b.youCount)}</span>
        </div>
      </div>
    </div>
  );
}

/** Window switcher + your summary card, cycling Today → 7 days → 30 days. */
export function WindowSwitcher() {
  const frame = useFrame();
  const win = frame % 3;
  return (
    <div aria-hidden className="font-mac flex flex-col gap-3.5 rounded-[18px] border border-mac-border bg-mac-panel p-3.5">
      <div className="flex items-center gap-0.5 self-center rounded-lg bg-mac-control p-0.5 text-[13px]">
        {["Today", "7 days", "30 days"].map((label, i) => (
          <span
            key={label}
            className={`rounded-md px-3 py-1 transition-colors duration-300 ${
              i === win ? "bg-lime font-semibold text-ink" : "text-mac-label"
            }`}
          >
            {label}
          </span>
        ))}
      </div>
      <div className="flex items-center gap-3 rounded-[14px] border border-lime/35 bg-lime/[.07] p-3.5">
        <img src={ME.avatar} alt="" className="size-11 shrink-0 rounded-full object-cover" />
        <span className="flex min-w-0 flex-1 flex-col leading-tight">
          <span className="text-sm font-bold">{ME.name}</span>
          <span className="text-[13px] font-semibold text-mac-gray">@{ME.handle}</span>
        </span>
        <span className="flex flex-col items-end">
          <span className="font-display text-[32px] leading-none font-extrabold tracking-[-0.04em] tabular-nums">
            {fmt(WINDOW_COUNTS[win])}
          </span>
          <span className="mt-1 text-[8px] font-semibold tracking-[.14em] text-[#aeaeb2]">CONTRIBUTIONS</span>
        </span>
      </div>
    </div>
  );
}

const PEOPLE_WINDOW = [
  { handle: "addisonk", canHide: false },
  { handle: "danielkinsner", canHide: true },
  { handle: "jamielottering", canHide: true },
  { handle: "jmzzll", canHide: true },
  { handle: "kropdx", canHide: true, toggles: true },
  { handle: "mvanhorn", canHide: true },
];

/** The People… window: search, source filter, eye toggles. */
export function PeopleWindow() {
  const frame = useFrame();
  return (
    <div
      aria-hidden
      className="font-mac min-w-0 flex-1 basis-[340px] overflow-hidden rounded-[14px] border border-mac-border bg-mac-window shadow-[0_30px_60px_-24px_rgba(0,0,0,.9)]"
    >
      <div className="flex h-[38px] items-center gap-2 border-b border-[#333] bg-mac-titlebar px-3">
        <span className="size-3 rounded-full bg-[#ff5f57]" />
        <span className="size-3 rounded-full bg-[#febc2e]" />
        <span className="size-3 rounded-full bg-[#28c840]" />
        <span className="mr-[52px] flex-1 text-center text-[13px] font-semibold text-mac-label">People</span>
      </div>
      <div className="flex flex-col gap-2.5 border-b border-[#2a2a2a] px-3 py-2.5">
        <div className="flex h-7 items-center gap-1.5 rounded-[7px] bg-mac-control px-2.5 text-[13px] text-mac-gray">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round">
            <circle cx="11" cy="11" r="7" />
            <path d="m20 20-3.5-3.5" />
          </svg>
          Search
        </div>
        <div className="flex gap-0.5 self-start rounded-[7px] bg-mac-control p-0.5 text-xs">
          <span className="rounded-[5px] bg-lime px-3 py-[3px] font-semibold text-ink">All</span>
          <span className="px-3 py-[3px] text-mac-label">Following</span>
          <span className="px-3 py-[3px] text-mac-label">Organizations</span>
        </div>
      </div>
      {PEOPLE_WINDOW.map((p) => {
        const hidden = !!p.toggles && frame % 2 === 1;
        return (
          <div
            key={p.handle}
            className={`flex h-10 items-center gap-2.5 border-b border-[#242424] px-3.5 transition-opacity duration-300 ${hidden ? "opacity-40" : ""}`}
          >
            <img src={avatar(p.handle)} alt="" className="size-6 shrink-0 rounded-full object-cover" />
            <span className="min-w-0 flex-1 truncate text-[13px] font-semibold">{p.handle}</span>
            {(!p.canHide || hidden) && <span className="text-[11px] text-mac-gray">{hidden ? "Hidden" : "You"}</span>}
            <span className="flex w-[22px] justify-center">
              {p.canHide &&
                (hidden ? (
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-mac-gray)" strokeWidth="2" strokeLinecap="round">
                    <path d="M3 3l18 18" />
                    <path d="M10.6 6.1A9.8 9.8 0 0 1 12 6c5 0 9 6 9 6a17 17 0 0 1-2.4 3" />
                    <path d="M6.6 6.6C4.3 8.1 3 12 3 12s4 6 9 6a9 9 0 0 0 4.4-1.1" />
                  </svg>
                ) : (
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--color-lime)" strokeWidth="2" strokeLinecap="round">
                    <path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z" />
                    <circle cx="12" cy="12" r="3" />
                  </svg>
                ))}
            </span>
          </div>
        );
      })}
    </div>
  );
}
