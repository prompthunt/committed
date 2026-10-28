export type DownloadPlatform = "mac" | "windows" | "unknown";

type BrowserPlatform = {
  userAgent: string;
  platform: string;
  maxTouchPoints: number;
  userAgentData?: { platform: string; mobile: boolean };
};

/** Match desktop installers; Apple mobile devices offer the Mac download. */
export function detectDownloadPlatform(browser: BrowserPlatform): DownloadPlatform {
  const { userAgent, platform, maxTouchPoints, userAgentData } = browser;
  // Apple mobile visitors get one Mac download, including iPad's desktop mode.
  if (/iPhone|iPad|iPod/i.test(userAgent) || (/Mac/i.test(platform) && maxTouchPoints > 1)) {
    return "mac";
  }
  if (userAgentData?.mobile || /Android|Mobile|Windows Phone/i.test(userAgent)) {
    return "unknown";
  }

  if (userAgentData?.platform) {
    if (userAgentData.platform === "Windows") return "windows";
    if (userAgentData.platform === "macOS") return "mac";
    return "unknown";
  }
  if (/Windows NT/i.test(userAgent)) return "windows";
  if (/Macintosh|Mac OS X/i.test(userAgent)) return "mac";
  return "unknown";
}

export function downloadTargets(platform: DownloadPlatform): string[] {
  if (platform === "windows") return ["Windows"];
  if (platform === "mac") return ["Mac"];
  return ["Mac", "Windows"];
}
