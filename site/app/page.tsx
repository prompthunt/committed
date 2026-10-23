import type { ReactNode } from "react";
import { AppIcon, Glyph } from "@/components/Glyph";
import { DemoMotionToggle, LoopProvider } from "@/components/useLoop";
import { HeroRankPill, MenuBarScene, NotificationStack, PeopleWindow, Popover, WindowSwitcher } from "@/components/MacUI";
import { DOWNLOAD_URL, RELEASES_URL } from "@/lib/board";

/* Deterministic contribution field behind the popover (same output on server and client). */
const FIELD = (() => {
  const scale = ["var(--color-sq-0)", "var(--color-sq-1)", "var(--color-sq-2)", "var(--color-sq-3)", "var(--color-lime)"];
  let seed = 21;
  const rnd = () => ((seed = (seed * 9301 + 49297) % 233280), seed / 233280);
  const cells: string[] = [];
  for (let w = 0; w < 27; w++)
    for (let d = 0; d < 14; d++) {
      const x = rnd() + (w / 27) * 0.5;
      cells.push(scale[x < 0.4 ? 0 : x < 0.65 ? 1 : x < 0.88 ? 2 : x < 1.12 ? 3 : 4]);
    }
  return cells;
})();

function DownloadIcon() {
  return (
    <svg aria-hidden width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 4v11" />
      <path d="m7 10 5 5 5-5" />
      <path d="M5 20h14" />
    </svg>
  );
}

function Check({ children }: { children: ReactNode }) {
  return (
    <li className="flex items-center gap-3">
      <span aria-hidden className="flex size-6 shrink-0 items-center justify-center rounded-[7px] bg-lime">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#050505" strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="m5 12 5 5 9-10" />
        </svg>
      </span>
      {children}
    </li>
  );
}

const tile = "rounded-[28px] border transition-[transform,border-color] duration-300 hover:-translate-y-1";
const darkTile = `${tile} border-white/[.08] bg-tile hover:border-lime/35`;

export default function Home() {
  return (
    <LoopProvider>
      <div className="flex min-h-svh flex-col overflow-x-hidden px-[clamp(20px,5vw,72px)]">
        <header className="flex min-h-[88px] items-center justify-between gap-4">
          <a href="/" className="flex items-center gap-2.5">
            <Glyph className="size-5 text-lime" />
            <span className="text-[19px] font-bold tracking-[-0.03em]">Committed</span>
          </a>
          <a href={RELEASES_URL} className="inline-flex min-h-11 items-center text-sm text-muted transition-colors hover:text-white">
            Release notes
          </a>
        </header>

        {/* HERO */}
        <main className="mx-auto flex w-full max-w-[1240px] flex-1 flex-wrap items-center justify-between gap-x-16 gap-y-14 pt-4 pb-12">
          <div className="flex min-w-0 flex-[1_1_440px] animate-rise flex-col gap-7">
            <AppIcon size={96} />
            <h1 className="text-[clamp(48px,6.2vw,92px)] leading-[0.96] font-[750] tracking-[-0.055em]">
              A little friendly <span className="text-lime">competition.</span>
            </h1>
            <ul className="flex flex-col gap-3 text-xl leading-snug text-soft">
              <Check>Compare GitHub contributions with friends</Check>
              <Check>Check your rank from the menu bar</Check>
              <Check>Reads counts, never your code</Check>
            </ul>
            <div className="flex flex-col items-start gap-3.5">
              <a
                href={DOWNLOAD_URL}
                className="inline-flex min-h-14 items-center gap-2.5 rounded-xl bg-lime px-6.5 text-[17px] font-semibold text-ink transition-[filter,box-shadow] duration-200 hover:shadow-[0_0_0_4px_rgba(200,255,46,.2),0_12px_36px_-10px_rgba(200,255,46,.55)] hover:brightness-105"
              >
                <DownloadIcon />
                Download for Mac
              </a>
              <span className="text-sm text-muted">macOS 26+ · Apple silicon &amp; Intel</span>
            </div>
          </div>

          <div
            className="relative flex min-w-0 flex-[0_1_380px] animate-rise flex-col items-center [animation-delay:150ms]"
          >
            <div role="img" aria-label="Committed's menu-bar popover: today's board, with Addison trading places with friends and finishing first" className="contents">
              <div aria-hidden className="contents">
                <div
                  aria-hidden
                  className="absolute top-[120px] left-1/2 w-[760px] -translate-x-1/2 overflow-hidden [mask-image:radial-gradient(closest-side,#000_30%,transparent)]"
                >
                  <div className="mx-auto grid w-max auto-cols-[22px] grid-flow-col grid-rows-[repeat(14,22px)] gap-1.5 opacity-55">
                    {FIELD.map((c, i) => (
                      <span key={i} className="size-[22px] rounded-[5px]" style={{ background: c }} />
                    ))}
                  </div>
                </div>
                <div className="font-mac relative mb-2 ml-3.5 self-start text-[17px]">
                  <HeroRankPill />
                </div>
                <div className="relative w-full flex justify-center">
                  <Popover />
                </div>
              </div>
            </div>
            <DemoMotionToggle />
          </div>
        </main>

        {/* FEATURES */}
        <section aria-label="Features" className="mx-auto w-full max-w-[1240px] pt-6 pb-24">
          <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
            <article className={`${tile} flex min-h-[360px] flex-wrap items-center justify-between gap-7 border-transparent bg-lime p-9 text-ink lg:col-span-2`}>
              <div className="flex min-w-0 flex-[1_1_300px] flex-col gap-3.5">
                <span className="text-xs font-bold tracking-[.12em]">RANK NOTIFICATIONS</span>
                <h2 className="text-[clamp(38px,4vw,56px)] leading-[0.95] font-[750] tracking-[-0.05em]">
                  Get a nudge when ranks change.
                </h2>
                <p className="text-[17px] leading-relaxed font-medium text-on-lime">
                  Get an alert when you pass a friend or they pass you. Opt in from the ⋯ menu.
                </p>
              </div>
              <div className="flex min-w-0 flex-[0_1_340px] justify-center">
                <NotificationStack />
              </div>
            </article>

            <article className={`${darkTile} flex min-h-[360px] flex-col justify-between gap-5 overflow-hidden pb-8`}>
              <MenuBarScene />
              <div className="flex flex-col gap-2 px-8">
                <h2 className="text-[25px] leading-tight font-bold tracking-[-0.03em]">Your rank at a glance</h2>
                <p className="text-[15px] leading-normal text-muted">
                  Keep an eye on your rank beside the app icon. Your board refreshes about every five minutes.
                </p>
              </div>
            </article>

            <article className={`${darkTile} flex min-h-[360px] flex-col justify-between gap-5 p-8`}>
              <WindowSwitcher />
              <div className="flex flex-col gap-2">
                <h2 className="text-[25px] leading-tight font-bold tracking-[-0.03em]">Pick your time frame</h2>
                <p className="text-[15px] leading-normal text-muted">
                  Compare today’s contributions, or look back over the past 7 or 30 days.
                </p>
              </div>
            </article>

            <article className={`${darkTile} flex min-h-[360px] flex-wrap items-center gap-9 p-9 lg:col-span-2`}>
              <div className="flex min-w-0 flex-[1_1_280px] flex-col gap-3">
                <span className="text-xs font-bold tracking-[.12em] text-lime">YOUR PEOPLE</span>
                <h2 className="text-[clamp(32px,3.4vw,46px)] leading-none font-[750] tracking-[-0.045em]">
                  No invites needed.
                </h2>
                <p className="text-base leading-normal text-muted">
                  Sign in with GitHub to load friends you follow and teammates from your organizations.
                  They don’t need Committed installed, and you choose who stays on your board.
                </p>
              </div>
              <PeopleWindow />
            </article>
          </div>
        </section>

        <footer className="mx-auto flex w-full max-w-[1240px] flex-wrap items-center justify-between gap-4 border-t border-white/[.08] pt-7 pb-10 text-sm text-muted">
          <span className="flex items-center gap-2.5">
            <Glyph className="size-4 text-lime" />
            Committed for macOS
          </span>
          <nav aria-label="Footer" className="flex flex-wrap gap-5">
            <a href={RELEASES_URL} className="py-2.5 hover:text-white">Release notes</a>
            <a href={DOWNLOAD_URL} className="py-2.5 hover:text-white">Download</a>
          </nav>
        </footer>
      </div>
    </LoopProvider>
  );
}
