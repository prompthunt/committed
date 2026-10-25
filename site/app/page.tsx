import { AppIcon, Glyph } from "@/components/Glyph";
import { AnalyticsLink } from "@/components/AnalyticsLink";
import { DemoMotionToggle, LoopProvider } from "@/components/useLoop";
import { HeroRankPill, Popover } from "@/components/MacUI";
import { FeatureGrid } from "@/components/FeatureGrid";
import { ContributionStrip } from "@/components/ContributionStrip";
import { HeroBackdrop } from "@/components/HeroBackdrop";
import { DOWNLOAD_URL, RELEASES_URL, SOURCE_URL } from "@/lib/board";

function DownloadIcon() {
  return (
    <svg aria-hidden width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 4v11" />
      <path d="m7 10 5 5 5-5" />
      <path d="M5 20h14" />
    </svg>
  );
}

export default function Home() {
  return (
    <LoopProvider>
      <div className="flex min-h-svh flex-col overflow-x-hidden px-[clamp(20px,5vw,72px)]">
        <header className="flex min-h-[88px] items-center justify-between gap-4">
          <a href="/" className="flex items-center gap-2.5">
            <Glyph className="size-5 text-lime" />
            <span className="text-[19px] font-bold tracking-[-0.03em]">Committed</span>
          </a>
          <nav aria-label="Main" className="flex items-center gap-3 sm:gap-5">
            <a href={RELEASES_URL} className="inline-flex min-h-11 items-center text-sm text-muted transition-colors hover:text-white">
              Release notes
            </a>
            <AnalyticsLink href={SOURCE_URL} event="github_clicked" placement="header" aria-label="View source on GitHub" title="View source on GitHub" className="inline-flex size-11 shrink-0 items-center justify-center rounded-lg text-muted transition-colors hover:text-white">
              <svg aria-hidden="true" width="22" height="22" viewBox="0 0 16 16" fill="currentColor">
                <path fillRule="evenodd" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
              </svg>
            </AnalyticsLink>
          </nav>
        </header>

        {/* HERO */}
        <main className="mx-auto flex w-full max-w-[1240px] flex-1 flex-col gap-y-14 pt-4 pb-12 lg:flex-row lg:items-center lg:justify-between lg:gap-x-16">
          <div className="flex min-w-0 animate-rise flex-col gap-7 lg:flex-[1_1_440px]">
            <AppIcon size={96} />
            <h1 className="text-[clamp(48px,6.2vw,92px)] leading-[0.96] font-[750] tracking-[-0.055em]">
              A little friendly <span className="text-lime">competition.</span>
            </h1>
            <div className="flex flex-col gap-3">
              <p className="max-w-[34rem] text-xl leading-relaxed text-soft">
                A GitHub leaderboard for your Mac’s menu bar. Connect GitHub to
                automatically add friends you follow and teammates from your organizations.
              </p>
              <p className="text-sm text-muted">No sign-up. Reads contribution counts, never your code.</p>
            </div>
            <div className="flex flex-col items-start gap-3.5">
              <AnalyticsLink
                href={DOWNLOAD_URL}
                event="download_clicked"
                placement="hero"
                className="inline-flex min-h-14 items-center gap-2.5 rounded-xl bg-lime px-6.5 text-[17px] font-semibold text-ink transition-[filter,box-shadow] duration-200 hover:shadow-[0_0_0_4px_rgba(200,255,46,.2),0_12px_36px_-10px_rgba(200,255,46,.55)] hover:brightness-105"
              >
                <DownloadIcon />
                Download for Mac
              </AnalyticsLink>
              <span className="text-sm text-muted">macOS 26+ · Apple silicon &amp; Intel</span>
            </div>
          </div>

          <div
            className="relative mt-12 flex w-full max-w-[380px] min-w-0 animate-rise flex-col items-center self-center [animation-delay:150ms] lg:mt-0 lg:flex-[0_1_380px] lg:self-auto"
          >
            <div role="img" aria-label="Committed's menu-bar popover: today's board, with Addison trading places with friends and finishing first" className="contents">
              <div aria-hidden className="contents">
                <HeroBackdrop />
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

        <ContributionStrip />

        <FeatureGrid />

        <footer className="mx-auto flex w-full max-w-[1240px] flex-wrap items-center justify-between gap-4 border-t border-white/[.08] pt-7 pb-10 text-sm text-muted">
          <span className="flex items-center gap-2.5">
            <Glyph className="size-4 text-lime" />
            Committed for macOS
          </span>
          <nav aria-label="Footer" className="flex flex-wrap gap-5">
            <a href={RELEASES_URL} className="py-2.5 hover:text-white">Release notes</a>
            <AnalyticsLink href={DOWNLOAD_URL} event="download_clicked" placement="footer" className="py-2.5 hover:text-white">Download</AnalyticsLink>
          </nav>
        </footer>
      </div>
    </LoopProvider>
  );
}
