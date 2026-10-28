"use client";

import { useSyncExternalStore } from "react";
import { AnalyticsLink } from "@/components/AnalyticsLink";
import { DOWNLOAD_URL, WINDOWS_DOWNLOAD_URL } from "@/lib/board";
import { detectDownloadPlatform, downloadTargets, type DownloadPlatform } from "@/lib/download-platform";
import { WINDOWS_DOWNLOAD_AVAILABLE } from "@/lib/site";

const unsubscribe = () => {};
const subscribe = () => unsubscribe;
const serverPlatform = (): DownloadPlatform => "unknown";
const clientPlatform = () => detectDownloadPlatform(navigator);

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
  // Static HTML and hydration both start with equal choices. No detection is
  // needed to follow the links when JavaScript is blocked. The OS stays fixed
  // for the lifetime of this page, so there is no browser event to subscribe to.
  const platform = useSyncExternalStore(subscribe, clientPlatform, serverPlatform);
  const platforms = downloadTargets(platform);
  const compact = placement === "footer";

  return (
    <div className={`flex flex-wrap items-center gap-x-5 gap-y-3 ${compact ? "" : "justify-center"}`} role="group" aria-label="Download Committed" data-download-platform={platform} data-placement={placement}>
      {platforms.map((target) => {
        if (target === "Windows" && !WINDOWS_DOWNLOAD_AVAILABLE) {
          return (
            <span key={target} className={compact ? "py-2.5 text-muted" : "inline-flex min-h-14 items-center rounded-xl border border-white/15 px-6.5 text-[17px] text-muted"}>
              Windows download coming soon
            </span>
          );
        }
        return (
          <AnalyticsLink
            key={target}
            href={target === "Windows" ? WINDOWS_DOWNLOAD_URL : DOWNLOAD_URL}
            event="download_clicked"
            placement={placement}
            className={compact
              ? "py-2.5 hover:text-white"
              : "inline-flex min-h-14 items-center gap-2.5 rounded-xl bg-lime px-6.5 text-[17px] font-semibold text-ink transition-[filter,box-shadow] duration-200 hover:shadow-[0_0_0_4px_rgba(200,255,46,.2),0_12px_36px_-10px_rgba(200,255,46,.55)] hover:brightness-105"}
          >
            {compact ? null : <DownloadIcon />}
            Download for {target}
          </AnalyticsLink>
        );
      })}
    </div>
  );
}
