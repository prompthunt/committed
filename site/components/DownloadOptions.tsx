"use client";

import { useSyncExternalStore } from "react";
import { AnalyticsLink } from "@/components/AnalyticsLink";
import { DOWNLOAD_URL, IPHONE_DOWNLOAD_URL, WINDOWS_DOWNLOAD_URL } from "@/lib/board";
import { detectDownloadPlatform, downloadTargets, type DownloadPlatform } from "@/lib/download-platform";
import { WINDOWS_DOWNLOAD_AVAILABLE } from "@/lib/site";

const unsubscribe = () => {};
const subscribe = () => unsubscribe;
const serverPlatform = (): DownloadPlatform => "unknown";
const clientPlatform = () => detectDownloadPlatform(navigator);

const DOWNLOADS = {
  iPhone: { url: IPHONE_DOWNLOAD_URL, requirement: "iOS 27.1+", label: "Get for iPhone" },
  Mac: { url: DOWNLOAD_URL, requirement: "macOS 26+", label: "Download for Mac" },
  Windows: { url: WINDOWS_DOWNLOAD_URL, requirement: "Windows 11 (x64)", label: "Download for Windows" },
};

function DownloadIcon() {
  return (
    <svg aria-hidden width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 4v11" />
      <path d="m7 10 5 5 5-5" />
      <path d="M5 20h14" />
    </svg>
  );
}

export function DownloadOptions({ placement }: { placement: "hero" | "closing" | "footer" }) {
  // Static HTML and hydration both start with all choices. No detection is
  // needed to follow the links when JavaScript is blocked. The OS stays fixed
  // for the lifetime of this page, so there is no browser event to subscribe to.
  const platform = useSyncExternalStore(subscribe, clientPlatform, serverPlatform);
  const platforms = downloadTargets(platform);
  const compact = placement === "footer";
  const hasWindowsOption = platforms.includes("Windows");
  const buttonWidth = hasWindowsOption ? "w-60" : "w-[10.5rem] sm:w-56";
  const buttonLayout = `inline-flex min-h-14 ${buttonWidth} max-w-full items-center justify-center gap-2.5 rounded-xl px-3 text-center text-[17px]`;
  const requirements = platforms.map((target) => DOWNLOADS[target].requirement);
  const showWindowsNote = placement === "hero" && WINDOWS_DOWNLOAD_AVAILABLE && hasWindowsOption;

  return (
    <>
      <div className={`flex flex-wrap items-center gap-y-3 ${compact ? "gap-x-5" : "justify-center gap-x-3"}`} role="group" aria-label="Download Committed" data-download-platform={platform} data-placement={placement}>
        {platforms.map((target, index) => {
          const primary = index === 0 || (platform === "unknown" && target === "Windows");
          return target === "Windows" && !WINDOWS_DOWNLOAD_AVAILABLE ? (
            <span key={target} className={compact ? "py-2.5 text-muted" : `${buttonLayout} border border-white/15 text-muted`}>
              Windows download coming soon
            </span>
          ) : (
            <AnalyticsLink
              key={target}
              href={DOWNLOADS[target].url}
              event="download_clicked"
              placement={placement}
              className={compact
                ? "py-2.5 hover:text-white"
                : `${buttonLayout} font-semibold ${primary
                  ? "bg-lime text-ink transition-[filter,box-shadow] duration-200 hover:shadow-[0_0_0_4px_rgba(200,255,46,.2),0_12px_36px_-10px_rgba(200,255,46,.55)] hover:brightness-105"
                  : "border border-white/20 text-white transition-colors hover:border-white/50"}`}
            >
              {!compact && primary && target !== "iPhone" && <DownloadIcon />}
              {DOWNLOADS[target].label}
            </AnalyticsLink>
          );
        })}
      </div>
      {!compact && <span className="text-sm text-muted">{[...(placement === "closing" ? ["Free"] : []), ...requirements].join(" · ")}</span>}
      {showWindowsNote && <p className="max-w-md text-sm leading-relaxed text-muted">The Windows installer is unsigned. If SmartScreen appears, choose <strong>More info → Run anyway</strong>.</p>}
    </>
  );
}
