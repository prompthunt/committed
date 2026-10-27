import posthog from "posthog-js";

let enabled = false;

export function initAnalytics() {
  const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;
  // Keep localhost, contributor builds, and Vercel previews out of launch numbers.
  if (!key || !["gitcommitted.app", "www.gitcommitted.app"].includes(window.location.hostname)) return;

  posthog.init(key, {
    api_host: "https://us.i.posthog.com",
    defaults: "2026-05-30",
    cookieless_mode: "always",
    person_profiles: "never",
    autocapture: false,
    capture_pageview: true,
    capture_pageleave: true,
    disable_session_recording: true,
    capture_exceptions: false,
    capture_performance: false,
    capture_dead_clicks: false,
    rageclick: false,
    enable_heatmaps: false,
    disable_surveys: true,
    advanced_disable_flags: true,
  });
  enabled = true;
}

export function captureLink(event: "download_clicked" | "github_clicked", placement: "hero" | "header" | "footer" | "closing") {
  if (!enabled) return;
  // Analytics must never delay or prevent the normal link / download behavior.
  try {
    posthog.capture(event, { placement }, { transport: "sendBeacon", send_instantly: true });
  } catch {
    // Navigation still works when analytics is unavailable.
  }
}
