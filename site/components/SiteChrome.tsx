import type { ReactNode } from "react";
import { Glyph } from "@/components/Glyph";
import { AnalyticsLink } from "@/components/AnalyticsLink";
import { DownloadOptions } from "@/components/DownloadOptions";
import { RELEASES_URL, SOURCE_URL } from "@/lib/board";
import { CONTACT_EMAIL } from "@/lib/site";

/** The header every page shares: the wordmark home, release notes, and the source link. */
export function SiteHeader() {
  return (
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
  );
}

/** The footer every page shares, with the privacy and support pages the App Store listing points at. */
export function SiteFooter() {
  return (
    <footer className="mx-auto mt-auto flex w-full max-w-[1240px] flex-wrap items-center justify-between gap-4 border-t border-white/[.08] pt-7 pb-10 text-sm text-muted">
      <span className="flex items-center gap-2.5">
        <Glyph className="size-4 text-lime" />
        Committed for Mac and Windows
      </span>
      <nav aria-label="Footer" className="flex flex-wrap gap-x-5">
        <a href={RELEASES_URL} className="py-2.5 hover:text-white">Release notes</a>
        <a href="/privacy" className="py-2.5 hover:text-white">Privacy</a>
        <a href="/support" className="py-2.5 hover:text-white">Support</a>
        <DownloadOptions placement="footer" />
      </nav>
    </footer>
  );
}

/** A plain reading page (privacy, support) in the site's look: header, a title block, prose, footer. */
export function ReadingPage({ eyebrow, title, intro, children }: { eyebrow: string; title: string; intro: ReactNode; children: ReactNode }) {
  return (
    <div className="isolate flex min-h-svh flex-col overflow-x-hidden px-[clamp(20px,5vw,72px)]">
      <SiteHeader />
      <main className="mx-auto w-full max-w-[44rem] pt-10 pb-[clamp(72px,9vw,128px)] sm:pt-16">
        <p className="font-mono text-[11px] font-medium tracking-[.06em] text-muted uppercase">{eyebrow}</p>
        <h1 className="mt-4 text-[clamp(42px,6vw,72px)] leading-[0.94] font-[750] tracking-[-0.055em] text-balance">{title}</h1>
        <div className="mt-6 space-y-4 text-xl leading-relaxed text-soft">{intro}</div>
        <div className="mt-[clamp(40px,5vw,64px)] space-y-[clamp(40px,5vw,56px)]">{children}</div>
      </main>
      <SiteFooter />
    </div>
  );
}

/** One titled section of a reading page. */
export function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section aria-labelledby={id} className="border-t border-white/[.08] pt-8">
      <h2 id={id} className="text-[clamp(26px,3.2vw,34px)] leading-[1.05] font-[750] tracking-[-0.04em] text-balance">{title}</h2>
      <div className="mt-5 space-y-4 text-base leading-relaxed text-soft sm:text-[17px] [&_a]:text-lime [&_a]:underline [&_a]:decoration-lime/40 [&_a]:underline-offset-4 [&_a:hover]:decoration-lime [&_strong]:font-semibold [&_strong]:text-white [&_code]:font-mono [&_code]:text-[0.9em] [&_code]:text-white [&_h3]:pt-2 [&_h3]:text-lg [&_h3]:font-semibold [&_h3]:tracking-[-0.01em] [&_h3]:text-white">
        {children}
      </div>
    </section>
  );
}

/** A bulleted list in a section. */
export function Bullets({ children }: { children: ReactNode }) {
  return <ul className="list-disc space-y-2.5 pl-5 marker:text-lime">{children}</ul>;
}

/**
 * The contact address, or a visible placeholder until one exists. The repo has no
 * contact address yet, so this never renders a made-up mailto link.
 */
export function ContactEmail() {
  if (CONTACT_EMAIL) return <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>;
  return <mark className="rounded bg-lime/15 px-1.5 py-0.5 font-mono text-[0.9em] text-lime">[contact email needed]</mark>;
}
