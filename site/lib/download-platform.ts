export type DownloadPlatform = "mac" | "windows" | "unknown";

type BrowserPlatform = {
  userAgent: string;
  platform: string;
  maxTouchPoints: number;
  userAgentData?: { platform: string; mobile: boolean };
};

/** Match desktop installers; phones, tablets and unknown browsers use the fallback. */
export function detectDownloadPlatform(browser: BrowserPlatform): DownloadPlatform {
  const { userAgent, platform, maxTouchPoints, userAgentData } = browser;
  // iPad's desktop mode reports MacIntel; it still isn't a Mac installer target.
  if (userAgentData?.mobile || /Android|iPhone|iPad|iPod|Mobile|Windows Phone/i.test(userAgent) || (/Mac/i.test(platform) && maxTouchPoints > 1)) {
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
