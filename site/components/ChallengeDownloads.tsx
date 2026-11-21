import { AnalyticsLink } from "@/components/AnalyticsLink";
import { DOWNLOAD_URL, IPHONE_DOWNLOAD_URL, WINDOWS_DOWNLOAD_URL } from "@/lib/board";
import { WINDOWS_DOWNLOAD_AVAILABLE } from "@/lib/site";

const BUTTON = "inline-flex min-h-14 w-full items-center justify-center rounded-xl px-6 text-[17px] font-semibold sm:w-auto";

/**
 * The challenge page's downloads: every platform at once, iPhone first, since a challenge arrives
 * on a phone. The site's other download groups adapt to the visitor's device.
 */
export function ChallengeDownloads() {
  return (
    <div role="group" aria-label="Get Committed" className="flex w-full flex-col items-stretch gap-3 sm:w-auto sm:flex-row sm:flex-wrap sm:justify-center">
      <AnalyticsLink
        href={IPHONE_DOWNLOAD_URL}
        event="download_clicked"
        placement="challenge"
        className={`${BUTTON} bg-lime text-ink transition-[filter,box-shadow] duration-200 hover:shadow-[0_0_0_4px_rgba(200,255,46,.2),0_12px_36px_-10px_rgba(200,255,46,.55)] hover:brightness-105`}
      >
        Get Committed for iPhone
      </AnalyticsLink>
      <AnalyticsLink href={DOWNLOAD_URL} aria-label="Get Committed for Mac" event="download_clicked" placement="challenge" className={`${BUTTON} border border-white/15 text-white transition-colors hover:border-white/35`}>
        Mac
      </AnalyticsLink>
      {WINDOWS_DOWNLOAD_AVAILABLE ? (
        <AnalyticsLink href={WINDOWS_DOWNLOAD_URL} aria-label="Get Committed for Windows" event="download_clicked" placement="challenge" className={`${BUTTON} border border-white/15 text-white transition-colors hover:border-white/35`}>
          Windows
        </AnalyticsLink>
      ) : (
        <span className={`${BUTTON} border border-white/10 font-normal text-muted`}>Windows coming soon</span>
      )}
    </div>
  );
}
