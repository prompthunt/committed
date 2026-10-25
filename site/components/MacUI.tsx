"use client";

import { Fragment, type ReactNode } from "react";
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

export const WINDOWS = ["Today", "7 days", "30 days"] as const;

/**
 * The popover's segmented Today / 7 days / 30 days picker (ContributionWindowPicker). Pass
 * `onSelect` to make it a real control; dividers sit between unselected neighbours, as in AppKit.
 */
export function WindowPicker({
  selected,
  onSelect,
  large = false,
  className = "",
}: {
  selected: number;
  onSelect?: (index: number) => void;
  large?: boolean;
  className?: string;
}) {
  const segment = `rounded-md px-3.5 whitespace-nowrap ${large ? "min-h-11 flex-1 text-[13px]" : "py-1"}`;
  return (
    <div
      role={onSelect ? "group" : undefined}
      aria-label={onSelect ? "Demo contribution time frame" : undefined}
      className={`font-mac flex items-center rounded-lg bg-mac-control p-0.5 text-[13px] ${className}`}
    >
      {WINDOWS.map((title, i) => {
        const on = i === selected;
        const style = `${segment} ${on ? "bg-mac-blue text-white" : "text-mac-label"}`;
        return (
          <Fragment key={title}>
            {i > 0 && i !== selected && i - 1 !== selected && <span aria-hidden className="h-3 w-px shrink-0 bg-[#48484a]" />}
            {onSelect ? (
              <button type="button" aria-pressed={on} onClick={() => onSelect(i)} className={`${style} cursor-pointer`}>
                {title}
              </button>
            ) : (
              <span className={style}>{title}</span>
            )}
          </Fragment>
        );
      })}
    </div>
  );
}

/** The summary card above the board: your avatar, name, handle and count for the window. */
export function YouSummary({ count }: { count: number }) {
  return (
    <div className="font-mac flex items-center gap-3 rounded-[14px] border border-mac-you-border bg-mac-you p-3.5 text-white">
      <img src={ME.avatar} alt="" className="size-[50px] shrink-0 rounded-full object-cover" />
      <span className="flex min-w-0 flex-1 flex-col leading-tight">
        <span className="text-sm font-bold">{ME.name}</span>
        <span className="text-sm font-semibold text-mac-gray">@{ME.handle}</span>
      </span>
      <span className="flex flex-col items-end">
        <span className="font-display text-[34px] leading-none font-extrabold tracking-[-0.04em] tabular-nums">
          {fmt(count)}
        </span>
        <span className="mt-1 text-[8px] font-semibold tracking-[.14em] text-[#aeaeb2]">CONTRIBUTIONS</span>
      </span>
    </div>
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
        <WindowPicker selected={0} className="self-center" />
        <YouSummary count={b.youCount} />
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

/* ── Crops of the app's other native screens, used by the feature grid ─────────────────── */

function GitHubMark({ className }: { className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 16 16" fill="currentColor" className={className}>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

function Symbol({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" className={className}>
      {children}
    </svg>
  );
}

const TRAFFIC = ["#ff5f57", "#febc2e", "#28c840"];

/** SignInView, signed out: the first screen of "Set up Committed", with its exact copy. */
export function ConnectScreen({ className = "" }: { className?: string }) {
  return (
    <div className={`font-mac flex w-[268px] flex-col items-center gap-3 rounded-[16px] border border-mac-border bg-mac-window px-5 pt-5 pb-4 text-center text-white ${className}`}>
      <GitHubMark className="size-[34px]" />
      <strong className="text-[13px] font-bold">Committed</strong>
      <span className="text-[11px] leading-snug text-mac-gray">
        See your standings alongside your organization members and people you follow. Your list updates automatically.
      </span>
      <span className="flex w-full items-center justify-center gap-2 rounded-lg bg-white py-2 text-[13px] font-semibold text-black">
        <GitHubMark className="size-4" />
        Connect GitHub
      </span>
      <span className="text-[10px] leading-snug text-mac-gray">
        Read-only access to your profile, who you follow, and your organizations. Committed never sees your code.
      </span>
    </div>
  );
}

const PEOPLE_ALPHABETICAL = ["addisonk", "danielkinsner", "jamielottering", "jmzzll", "kropdx", "mvanhorn"];

/** The People… window (FullRankingsView): search, source filter, and one visibility row per person. */
export function PeopleWindow({ className = "" }: { className?: string }) {
  return (
    <div className={`font-mac flex flex-col overflow-hidden rounded-[12px] border border-mac-border bg-mac-window text-white shadow-[0_24px_50px_-20px_#000] ${className}`}>
      <div className="flex h-[38px] shrink-0 items-center gap-3 border-b border-black/60 bg-mac-titlebar px-3">
        <span className="flex gap-2">
          {TRAFFIC.map((c) => <span key={c} className="size-3 rounded-full" style={{ background: c }} />)}
        </span>
        <span className="text-[13px] font-bold">People</span>
        <span className="ml-auto flex min-w-0 items-center gap-1.5 rounded-md bg-white/[.08] px-2 py-1 text-[11px] text-mac-gray">
          <Symbol className="size-3 shrink-0"><circle cx="11" cy="11" r="6" /><path d="m20 20-4.5-4.5" /></Symbol>
          <span className="truncate">Find a GitHub username</span>
        </span>
      </div>
      <div className="flex flex-col gap-2.5 p-3.5">
        <span className="text-[12px] text-mac-gray">Choose who appears on your leaderboard.</span>
        <span className="flex rounded-lg bg-mac-control p-0.5 text-[12px]">
          <span className="flex-1 rounded-md bg-mac-blue py-[3px] text-center text-white">All</span>
          <span className="flex-1 py-[3px] text-center text-mac-label">Following</span>
          <span aria-hidden className="my-auto h-3 w-px bg-[#48484a]" />
          <span className="flex-1 py-[3px] text-center text-mac-label">Organizations</span>
        </span>
        <span className="text-[11px] text-mac-gray">Synced 2 min ago</span>
      </div>
      <ul className="border-t border-mac-divider px-2 py-1">
        {PEOPLE_ALPHABETICAL.map((handle) => (
          <li key={handle} className="flex h-[34px] items-center gap-2.5 border-b border-mac-divider px-1.5 last:border-b-0">
            <img src={avatar(handle)} alt="" className="size-6 shrink-0 rounded-full object-cover" />
            <span className="min-w-0 flex-1 truncate text-[13px]">@{handle}</span>
            {handle === ME.handle ? (
              <span className="text-[11px] text-mac-gray">You</span>
            ) : (
              <Symbol className="size-[18px] text-mac-blue">
                <path d="M2 12s3.6-6.5 10-6.5S22 12 22 12s-3.6 6.5-10 6.5S2 12 2 12Z" />
                <circle cx="12" cy="12" r="2.8" />
              </Symbol>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

/** PrivateContributionsTip as it appears in the popover and the explainer window. */
export function PrivateTip({ className = "" }: { className?: string }) {
  return (
    <div className={`font-mac flex w-[272px] flex-col gap-1.5 rounded-[10px] border border-mac-you-border bg-mac-you p-[11px] text-white ${className}`}>
      <span className="flex items-center gap-2 text-[13px] font-semibold">
        <Symbol className="size-4 shrink-0 text-mac-you-text">
          <rect x="5" y="11" width="14" height="10" rx="2" />
          <path d="M8.5 11V7.5a3.5 3.5 0 0 1 6.8-1.2" />
        </Symbol>
        Want your private work to count?
      </span>
      <span className="text-[11px] leading-snug text-mac-gray">Only daily counts are shared. Your code and repo details stay private.</span>
    </div>
  );
}

/** The Committed menu-bar item (MenuBarLabel), highlighted as when its popover is open. */
export function MenuBarStrip({ rank, className = "" }: { rank: number; className?: string }) {
  return (
    <div className={`font-mac flex h-9 items-center gap-3.5 border-y border-white/10 bg-white/[.09] px-3 text-[14px] whitespace-nowrap text-mac-label ${className}`}>
      <RankPill rank={rank} className="px-2.5 py-[3px]" />
      <Symbol className="size-4 shrink-0">
        <path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a5.5 5.5 0 0 1 7 0" />
        <circle cx="12" cy="19" r=".6" fill="currentColor" />
      </Symbol>
      <span>Wed 4:12 PM</span>
    </div>
  );
}

const MENU_CHECKS = ["Automatic Updates", "Launch at Login", "Leaderboard Notifications"];

/** The ⋯ overflow menu's native checkbox rows (OverflowMenu). */
export function OverflowChecks({ className = "" }: { className?: string }) {
  return (
    <div className={`font-mac flex w-[230px] flex-col gap-px rounded-[10px] border border-white/15 bg-[#262628]/95 p-1.5 text-[13px] text-white shadow-[0_18px_40px_-16px_rgba(0,0,0,.7)] ${className}`}>
      {MENU_CHECKS.map((title) => (
        <span key={title} className="flex items-center gap-2 px-2 py-[5px]">
          <span className="grid size-[14px] shrink-0 place-items-center rounded-[4px] bg-mac-blue">
            <Symbol className="size-[11px] text-white"><path d="m5 12.5 4.5 4.5L19 7.5" strokeWidth={3} /></Symbol>
          </span>
          {title}
        </span>
      ))}
    </div>
  );
}
