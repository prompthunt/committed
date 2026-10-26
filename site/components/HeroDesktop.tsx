"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { NotificationStack, Popover } from "./MacUI";
import { Glyph } from "./Glyph";
import { DemoMotionToggle, FrameOverride, useMotionPaused } from "./useLoop";
import { board } from "@/lib/board";
import { seeded, SQUARE_SCALE } from "@/lib/contributions";

/*
 * The hero's Mac desktop: a full-bleed wallpaper under a real macOS menu bar, with the
 * Committed popover hanging from its menu-bar item. A short timeline plays the app in use:
 * banners arrive while you work, you open the board, pass a friend live, then close it.
 */

type Cursor = "hidden" | "desk" | "pill" | "card";
type Step = { at: number; frame: number; open: boolean; banners: boolean; cursor: Cursor; click?: boolean; burst?: boolean };

const STEPS: Step[] = [
  { at: 0, frame: 0, open: false, banners: true, cursor: "hidden" },
  { at: 1000, frame: 1, open: false, banners: true, cursor: "hidden", burst: true },
  { at: 3000, frame: 2, open: false, banners: true, cursor: "hidden" },
  { at: 4600, frame: 2, open: false, banners: true, cursor: "desk" },
  { at: 4900, frame: 2, open: false, banners: true, cursor: "pill" },
  { at: 6000, frame: 2, open: true, banners: false, cursor: "pill", click: true },
  { at: 7000, frame: 2, open: true, banners: false, cursor: "card" },
  { at: 7800, frame: 3, open: true, banners: false, cursor: "card", burst: true },
  { at: 10300, frame: 3, open: true, banners: false, cursor: "desk" },
  { at: 11300, frame: 3, open: false, banners: false, cursor: "desk", click: true },
  { at: 12100, frame: 0, open: false, banners: false, cursor: "hidden" },
];
const LOOP = 12900;
/** Start where the board is already open, so the first thing you see is the app. */
const FIRST_STEP = 6;
const RESTING: Step = { at: 0, frame: 3, open: true, banners: false, cursor: "hidden" };

const vars = (v: Record<string, string | number>) => v as CSSProperties;

/** Contribution squares that pop out of the menu-bar item when you take first place. */
const BURST = (() => {
  const rnd = seeded(11);
  return Array.from({ length: 18 }, (_, i) => {
    const angle = Math.PI * (0.1 + 0.8 * (i / 17)) + (rnd() - 0.5) * 0.3;
    const dist = 46 + rnd() * 70;
    return {
      x: Math.cos(angle) * dist * (i % 2 ? 1 : -1),
      y: Math.sin(angle) * dist * 0.55 + 18,
      size: 5 + Math.round(rnd() * 5),
      color: SQUARE_SCALE[2 + Math.floor(rnd() * 3)],
      spin: Math.round((rnd() - 0.5) * 540),
      delay: Math.round(rnd() * 90),
    };
  });
})();

function AppleLogo() {
  return (
    <svg aria-hidden viewBox="0 0 24 24" fill="currentColor" className="size-[17px] -translate-y-px">
      <path d="M16.37 12.6c-.02-2.3 1.88-3.4 1.96-3.46-1.07-1.56-2.73-1.78-3.32-1.8-1.41-.14-2.76.83-3.48.83-.72 0-1.83-.81-3-.79-1.55.02-2.97.9-3.77 2.28-1.61 2.79-.41 6.92 1.16 9.18.77 1.1 1.68 2.35 2.88 2.3 1.16-.05 1.6-.75 3-.75s1.8.75 3.02.72c1.25-.02 2.04-1.12 2.8-2.23.88-1.28 1.24-2.53 1.26-2.59-.03-.01-2.42-.93-2.44-3.69zM14.1 5.86c.64-.78 1.07-1.85.95-2.93-.92.04-2.04.61-2.7 1.39-.59.69-1.11 1.79-.97 2.85 1.03.08 2.07-.52 2.72-1.31z" />
    </svg>
  );
}

function StatusIcon({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round" className={`size-4 shrink-0 ${className}`}>
      {children}
    </svg>
  );
}

const APP_MENUS = ["File", "Edit", "View", "Go", "Window", "Help"];

function usePrefersReducedMotion() {
  const [reduce, setReduce] = useState(false);
  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduce(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  return reduce;
}

export function HeroDesktop() {
  const scene = useRef<HTMLDivElement>(null);
  const pill = useRef<HTMLSpanElement>(null);
  const pop = useRef<HTMLDivElement>(null);
  const reduce = usePrefersReducedMotion();
  const paused = useMotionPaused();
  const [index, setIndex] = useState(FIRST_STEP);
  const [onScreen, setOnScreen] = useState(true);
  const [layout, setLayout] = useState<{ popLeft: number; originX: number; cursor: Record<Cursor, [number, number]> } | null>(null);

  const step = reduce ? RESTING : STEPS[index];
  const { youRank } = board(step.frame);

  // Advance the timeline; hold still while paused, off screen, or for reduced motion.
  useEffect(() => {
    if (reduce || paused || !onScreen) return;
    const next = (index + 1) % STEPS.length;
    const wait = (next === 0 ? LOOP : STEPS[next].at) - STEPS[index].at;
    const id = window.setTimeout(() => setIndex(next), wait);
    return () => window.clearTimeout(id);
  }, [index, paused, onScreen, reduce]);

  useEffect(() => {
    const node = scene.current;
    if (!node) return;
    const io = new IntersectionObserver(([entry]) => setOnScreen(entry.isIntersecting), { threshold: 0.15 });
    io.observe(node);
    return () => io.disconnect();
  }, []);

  // Hang the popover under the menu-bar item and work out where the cursor travels.
  const measure = useCallback(() => {
    const s = scene.current, p = pill.current, card = pop.current;
    if (!s || !p || !card) return;
    const sr = s.getBoundingClientRect(), pr = p.getBoundingClientRect();
    const width = Math.min(340, sr.width - 32);
    const pillX = pr.left + pr.width / 2 - sr.left;
    const popLeft = Math.max(16, Math.min(sr.width - 16 - width, pillX - width / 2));
    const summary = card.querySelector<HTMLElement>("[data-you-summary]")?.getBoundingClientRect();
    const popTop = card.getBoundingClientRect().top - sr.top;
    setLayout({
      popLeft,
      originX: pillX - popLeft,
      cursor: {
        hidden: [sr.width * 0.34, sr.height * 0.62],
        desk: [sr.width * 0.3, sr.height * 0.55],
        pill: [pillX - 2, pr.top - sr.top + pr.height * 0.55],
        card: summary ? [summary.left - sr.left + summary.width * 0.62, summary.top - sr.top + summary.height * 0.45] : [popLeft + width * 0.6, popTop + 140],
      },
    });
  }, []);

  useLayoutEffect(() => {
    measure();
    const ro = new ResizeObserver(measure);
    if (scene.current) ro.observe(scene.current);
    return () => ro.disconnect();
  }, [measure]);

  const [cx, cy] = layout?.cursor[step.cursor] ?? [0, 0];

  return (
    <section
      aria-label="Committed's menu-bar popover on a Mac desktop: notifications arrive as friends trade places, then the board opens and Addison takes first"
      data-paused={paused || undefined}
      className="desk-frame desk relative max-sm:-mx-[clamp(20px,5vw,72px)] sm:mx-auto sm:w-full sm:max-w-[1240px]"
    >
      {/* The screen: edge to edge on phones, a framed display with a bezel from sm up. */}
      <div ref={scene} className="desk-screen relative overflow-hidden">
      <div aria-hidden className="desk-wallpaper absolute inset-0"><i /><i /></div>
      <FrameOverride frame={step.frame}>
        <div aria-hidden className="font-mac relative">
          {/* Menu bar: app menus on the left, menu-bar extras and the clock on the right. */}
          <div className="desk-menubar relative z-20 flex h-9 items-center gap-5 bg-black/30 px-5 text-[13.5px] text-mac-label backdrop-blur-xl max-sm:gap-4 max-sm:px-3">
            <AppleLogo />
            <span className="font-bold text-white">Finder</span>
            {APP_MENUS.map((menu) => (
              <span key={menu} className="max-lg:hidden">{menu}</span>
            ))}
            <span className="ml-auto flex items-center gap-[18px] whitespace-nowrap max-sm:gap-3">
              <span
                ref={pill}
                data-open={step.open || undefined}
                className="desk-pill relative inline-flex items-center gap-1.5 rounded-full bg-white/15 px-3 py-[5px] text-[13px] font-semibold text-white"
              >
                <Glyph className="size-[1.05em]" />
                <span className="inline-flex overflow-hidden">
                  <span key={youRank} className="desk-rank tabular-nums">#{youRank}</span>
                </span>
                <span className="desk-burst">
                  {step.burst && (
                    <span key={index}>
                      <i className="desk-flash" />
                      {BURST.map((b, i) => (
                        <i
                          key={i}
                          style={vars({ "--x": `${b.x}px`, "--y": `${b.y}px`, "--s": `${b.size}px`, "--c": b.color, "--r": `${b.spin}deg`, "--d": `${b.delay}ms` })}
                        />
                      ))}
                    </span>
                  )}
                </span>
              </span>
              <StatusIcon>
                <path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a5.5 5.5 0 0 1 7 0" />
                <circle cx="12" cy="19" r=".6" fill="currentColor" />
              </StatusIcon>
              <StatusIcon className="w-[22px]">
                <rect x="2" y="7" width="17" height="10" rx="2.5" />
                <rect x="4" y="9" width="11" height="6" rx="1" fill="currentColor" stroke="none" />
                <path d="M21.5 10.5v3" />
              </StatusIcon>
              <StatusIcon className="max-sm:hidden">
                <circle cx="11" cy="11" r="6" />
                <path d="m20 20-4.5-4.5" />
              </StatusIcon>
              <StatusIcon className="max-sm:hidden">
                <rect x="3" y="5" width="18" height="6" rx="3" />
                <circle cx="15" cy="8" r="1.6" fill="currentColor" />
                <rect x="3" y="13" width="18" height="6" rx="3" />
                <circle cx="9" cy="16" r="1.6" fill="currentColor" />
              </StatusIcon>
              <span className="max-sm:hidden">Wed 4:12 PM</span>
              <span className="sm:hidden">4:12</span>
            </span>
          </div>

          {/* Banners arrive top-right while the board is closed. */}
          <div data-show={step.banners || undefined} className="desk-banners absolute top-12 right-4 z-10 w-[calc(100%-32px)] max-w-[340px]">
            <NotificationStack />
          </div>

          {/* The popover hangs from the Committed item, centred under it and kept on screen. */}
          <div className="px-4 pt-2 pb-24 sm:pb-16">
            <div
              ref={pop}
              data-open={step.open || undefined}
              className="desk-pop w-[340px] max-w-full"
              style={layout ? { marginLeft: layout.popLeft - 16, ...vars({ "--origin-x": `${layout.originX}px` }) } : { marginLeft: "auto", marginRight: "auto" }}
            >
              <Popover />
            </div>
          </div>

          {/* The pointer: glides between targets and clicks. */}
          {layout && (
            <span
              data-show={step.cursor !== "hidden" || undefined}
              className="desk-cursor pointer-events-none absolute top-0 left-0 z-30"
              style={{ transform: `translate(${cx}px, ${cy}px)` }}
            >
              <span key={step.click ? index : "idle"} data-click={step.click || undefined} className="desk-cursor-body">
                <svg viewBox="0 0 24 24" className="size-[22px] drop-shadow-[0_2px_3px_rgba(0,0,0,.5)]">
                  <path d="M5 2.5v17.2l4.3-4.2 2.9 6.6 2.7-1.2-2.8-6.4h6.2Z" fill="#000" stroke="#fff" strokeWidth="1.4" strokeLinejoin="round" />
                </svg>
                {step.click && <i className="desk-ripple" />}
              </span>
            </span>
          )}
        </div>
      </FrameOverride>
      <div className="absolute right-5 bottom-5 z-30 size-11">
        <DemoMotionToggle />
      </div>
      </div>
    </section>
  );
}
