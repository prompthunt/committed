import { SiteFooter, SiteHeader } from "@/components/SiteChrome";
import { LoopProvider } from "@/components/useLoop";
import { HeroDesktop } from "@/components/HeroDesktop";
import { FeatureGrid } from "@/components/FeatureGrid";
import { SquareField } from "@/components/SquareField";
import { Faq } from "@/components/Faq";
import { DownloadOptions } from "@/components/DownloadOptions";
import { DOWNLOAD_URL, WINDOWS_DOWNLOAD_URL, SOURCE_URL } from "@/lib/board";
import { DESCRIPTION, FAQ, SITE_URL, WINDOWS_DOWNLOAD_AVAILABLE } from "@/lib/site";

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
        <SiteHeader />

        {/* HERO */}
        <main className="mx-auto flex w-full max-w-[1240px] flex-col items-center gap-6 pt-10 pb-[clamp(64px,9vw,144px)] text-center sm:pt-16 lg:pt-32">
          <h1 className="max-w-[14ch] animate-rise text-[clamp(46px,7vw,96px)] leading-[0.94] font-[750] tracking-[-0.055em] text-balance">
            Who shipped more <span className="text-lime">today?</span>
          </h1>
          <p className="max-w-[30rem] animate-rise text-xl leading-relaxed text-soft [animation-delay:90ms]">Your GitHub leaderboard, in the Mac menu bar or Windows tray.</p>
          <div className="mt-2 flex animate-rise flex-col items-center gap-3.5 [animation-delay:180ms]">
            <DownloadOptions placement="hero" />
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
            <DownloadOptions placement="closing" />
            <span className="text-sm text-muted">Free · macOS 26+ · Windows 11 (x64)</span>
          </div>
        </section>

        <SiteFooter />
      </div>
    </LoopProvider>
  );
}
