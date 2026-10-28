import { Glyph } from "@/components/Glyph";
import { AnalyticsLink } from "@/components/AnalyticsLink";
import { LoopProvider } from "@/components/useLoop";
import { HeroDesktop } from "@/components/HeroDesktop";
import { FeatureGrid } from "@/components/FeatureGrid";
import { SquareField } from "@/components/SquareField";
import { Faq } from "@/components/Faq";
import { DOWNLOAD_URL, WINDOWS_DOWNLOAD_URL, RELEASES_URL, SOURCE_URL } from "@/lib/board";
import { DESCRIPTION, FAQ, SITE_URL, WINDOWS_DOWNLOAD_AVAILABLE } from "@/lib/site";

function DownloadIcon() {
  return (
    <svg aria-hidden width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 4v11" />
      <path d="m7 10 5 5 5-5" />
      <path d="M5 20h14" />
    </svg>
  );
}

function DownloadButton({ placement, platform = "Mac" }: { placement: "hero" | "closing"; platform?: "Mac" | "Windows" }) {
  if (platform === "Windows" && !WINDOWS_DOWNLOAD_AVAILABLE) {
    return <span className="inline-flex min-h-14 items-center rounded-xl border border-white/15 px-6.5 text-[17px] text-muted">Windows download coming soon</span>;
  }
  return (
    <AnalyticsLink
      href={platform === "Windows" ? WINDOWS_DOWNLOAD_URL : DOWNLOAD_URL}
      event="download_clicked"
      placement={placement}
      className="inline-flex min-h-14 items-center gap-2.5 rounded-xl bg-lime px-6.5 text-[17px] font-semibold text-ink transition-[filter,box-shadow] duration-200 hover:shadow-[0_0_0_4px_rgba(200,255,46,.2),0_12px_36px_-10px_rgba(200,255,46,.55)] hover:brightness-105"
    >
      <DownloadIcon />
      Download for {platform}
    </AnalyticsLink>
  );
}

// What search engines and AI answer engines read: the app itself, and the FAQ shown on the page.
const STRUCTURED_DATA = [
  {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "Committed",
    description: DESCRIPTION,
    url: SITE_URL,
    applicationCategory: "DeveloperApplication",
    operatingSystem: ["macOS 26 or later", "Windows 11"],
    downloadUrl: WINDOWS_DOWNLOAD_AVAILABLE ? [DOWNLOAD_URL, WINDOWS_DOWNLOAD_URL] : DOWNLOAD_URL,
    license: "https://opensource.org/licenses/MIT",
    isAccessibleForFree: true,
    offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    sameAs: [SOURCE_URL],
  },
  {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: FAQ.map(({ q, a }) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: a } })),
  },
];

export default function Home() {
  return (
    <LoopProvider>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(STRUCTURED_DATA).replace(/</g, "\\u003c") }} />
      <div className="isolate flex min-h-svh flex-col overflow-x-hidden px-[clamp(20px,5vw,72px)]">
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
        <main className="mx-auto flex w-full max-w-[1240px] flex-col items-center gap-6 pt-10 pb-[clamp(64px,9vw,144px)] text-center sm:pt-16 lg:pt-32">
          <h1 className="max-w-[14ch] animate-rise text-[clamp(46px,7vw,96px)] leading-[0.94] font-[750] tracking-[-0.055em] text-balance">
            Who shipped more <span className="text-lime">today?</span>
          </h1>
          <p className="max-w-[30rem] animate-rise text-xl leading-relaxed text-soft [animation-delay:90ms]">Your GitHub leaderboard, in the Mac menu bar or Windows tray.</p>
          <div className="mt-2 flex animate-rise flex-col items-center gap-3.5 [animation-delay:180ms]">
            <div className="flex flex-wrap justify-center gap-3"><DownloadButton placement="hero" /><DownloadButton placement="hero" platform="Windows" /></div>
            <span className="text-sm text-muted">macOS 26+ · Windows 11 (x64)</span>
            <p className="max-w-md text-sm leading-relaxed text-muted">The Windows installer is unsigned. If SmartScreen appears, choose <strong>More info → Run anyway</strong>.</p>
          </div>
        </main>

        <SquareField>
          <HeroDesktop />
        </SquareField>

        <FeatureGrid />

        <Faq />

        {/* CLOSING */}
        <section aria-labelledby="closing-title" className="mx-auto flex w-full max-w-[1240px] flex-col items-center gap-6 pt-[clamp(96px,12vw,176px)] pb-[clamp(72px,9vw,128px)] text-center">
          <h2 id="closing-title" className="max-w-[16ch] text-[clamp(38px,5.6vw,72px)] leading-[0.94] font-[750] tracking-[-0.055em] text-balance">
            Start your <span className="text-lime">leaderboard.</span>
          </h2>
          <div className="mt-2 flex flex-col items-center gap-3.5">
            <div className="flex flex-wrap justify-center gap-3"><DownloadButton placement="closing" /><DownloadButton placement="closing" platform="Windows" /></div>
            <span className="text-sm text-muted">Free · macOS 26+ · Windows 11 (x64)</span>
          </div>
        </section>

        <footer className="mx-auto flex w-full max-w-[1240px] flex-wrap items-center justify-between gap-4 border-t border-white/[.08] pt-7 pb-10 text-sm text-muted">
          <span className="flex items-center gap-2.5">
            <Glyph className="size-4 text-lime" />
            Committed for Mac and Windows
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
